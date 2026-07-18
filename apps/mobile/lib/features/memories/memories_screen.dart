import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';
import 'video_view_screen.dart';

class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key});

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final bool _helper;
  List<dynamic> _approved = [];
  List<dynamic> _pending = [];
  List<dynamic> _mine = [];
  String? _error;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _helper = ref.read(authProvider).isLeaderOrVolunteer;
    _tabs = TabController(length: _helper ? 3 : 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String _url(Map<String, dynamic> m) {
    final api = ref.read(apiClientProvider);
    final path = m['url_path']?.toString() ?? '';
    if (path.startsWith('http')) return path;
    return '${api.baseUrl}$path';
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final approved = await api.get('/media') as List<dynamic>;
      final mine = await api.get('/media/mine') as List<dynamic>;
      List<dynamic> pending = [];
      if (_helper) {
        pending = await api.get('/media/pending') as List<dynamic>;
      }
      setState(() {
        _approved = approved;
        _mine = mine;
        _pending = pending;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load memories.');
    }
  }

  String _contentTypeFor(XFile file, bool video) {
    final mime = file.mimeType;
    if (mime != null && (mime.startsWith('image/') || mime.startsWith('video/'))) {
      return mime;
    }
    final name = file.name.toLowerCase();
    final ext = name.contains('.') ? name.split('.').last : '';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case '3gp':
        return 'video/3gpp';
      default:
        return video ? 'video/mp4' : 'image/jpeg';
    }
  }

  Future<void> _chooseSource() async {
    final choice = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Photo'),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video'),
              subtitle: const Text('Up to 3 minutes'),
              onTap: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await _pickAndUpload(video: choice);
  }

  Future<void> _pickAndUpload({required bool video}) async {
    final picker = ImagePicker();
    final XFile? file = video
        ? await picker.pickVideo(
            source: ImageSource.gallery,
            maxDuration: const Duration(minutes: 3),
          )
        : await picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 80,
            maxWidth: 1920,
          );
    if (file == null) return;
    if (!mounted) return;

    final captionCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(video ? 'Share video' : 'Share memory'),
        content: TextField(
          controller: captionCtrl,
          decoration: const InputDecoration(
            labelText: 'Caption (optional)',
            hintText: 'Swamiye Sharanam…',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Upload')),
        ],
      ),
    );
    final caption = captionCtrl.text.trim();
    captionCtrl.dispose();
    if (ok != true) return;

    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final contentType = _contentTypeFor(file, video);
      final api = ref.read(apiClientProvider);

      // 1. Ask the API for an upload target (S3 presigned or local blob URL).
      final presign = await api.post('/media/presign', body: {
        'content_type': contentType,
      });
      final uploadUrl = presign['upload_url']?.toString() ?? '';
      final key = presign['key']?.toString() ?? '';
      final rawHeaders = presign['headers'];
      final signedHeaders = <String, String>{};
      if (rawHeaders is Map) {
        rawHeaders.forEach((k, v) => signedHeaders[k.toString()] = v.toString());
      }
      final putContentType = signedHeaders['Content-Type'] ?? contentType;

      // 2. Upload the bytes directly to storage, echoing every signed header.
      await api.putBinary(
        uploadUrl,
        bytes: bytes,
        contentType: putContentType,
        signedHeaders: signedHeaders,
      );

      // 3. Persist the media row.
      final res = await api.post('/media/confirm', body: {
        'key': key,
        'content_type': contentType,
        'byte_size': bytes.length,
        if (caption.isNotEmpty) 'caption': caption,
      });

      await _load();
      if (mounted) {
        final approved = res['approved'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approved
                  ? 'Memory shared with the group'
                  : 'Uploaded — waiting for leader approval',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Upload failed. Try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _approve(String id) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/media/$id/approve');
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not approve photo.');
    }
  }

  Future<void> _reject(String id) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/media/$id/reject');
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not reject photo.');
    }
  }

  Widget _videoThumb(Map<String, dynamic> m) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoViewScreen(
            url: _url(m),
            caption: m['caption']?.toString(),
          ),
        ),
      ),
      child: Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: const Icon(
          Icons.play_circle_outline,
          color: Colors.white,
          size: 48,
        ),
      ),
    );
  }

  Widget _grid(List<dynamic> items, {bool moderate = false}) {
    final c = context.sharanam;
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.photo_library_outlined,
        message: 'No photos yet',
        detail: 'Swamiye Sharanam — share a memory.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final m = Map<String, dynamic>.from(items[i] as Map);
        final isVideo = m['is_video'] == true;
        return SectionCard(
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: isVideo
                      ? _videoThumb(m)
                      : Image.network(
                          _url(m),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m['uploader_name']?.toString() ?? '',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    if (m['caption'] != null)
                      Text(
                        m['caption'].toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (moderate)
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Approve',
                            onPressed: () => _approve(m['id'].toString()),
                            icon: Icon(Icons.check_circle, color: c.success),
                          ),
                          IconButton(
                            tooltip: 'Reject',
                            onPressed: () => _reject(m['id'].toString()),
                            icon: Icon(Icons.cancel_outlined, color: c.danger),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memories'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'Gallery'),
            const Tab(text: 'My uploads'),
            if (_helper) Tab(text: 'Pending (${_pending.length})'),
          ],
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _chooseSource,
        icon: _uploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_a_photo_outlined),
        label: Text(_uploading ? 'Uploading…' : 'Add memory'),
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: StatusBanner(
                kind: StatusBannerKind.danger,
                message: _error!,
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _grid(_approved),
                _grid(_mine),
                if (_helper) _grid(_pending, moderate: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

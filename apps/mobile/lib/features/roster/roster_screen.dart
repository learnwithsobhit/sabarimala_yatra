import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';

class RosterScreen extends ConsumerStatefulWidget {
  const RosterScreen({super.key});

  @override
  ConsumerState<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends ConsumerState<RosterScreen> {
  List<dynamic> _members = [];
  String? _error;
  bool _loading = true;
  final _csv = TextEditingController(
    text: 'phone,name,role,kanni,senior,years\n'
        '9999000010,New Swamy,swamy,false,false,1\n',
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _csv.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final members = await api.get('/roster') as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _members = members;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load roster. Check network and try again.';
        _loading = false;
      });
    }
  }

  String? _photoUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    return '${ref.read(apiClientProvider).baseUrl}$raw';
  }

  Future<void> _markNotTraveling(Map<String, dynamic> m) async {
    final auth = ref.read(authProvider);
    if (!auth.isLeaderOrVolunteer) return;
    final id = m['id']?.toString() ?? m['member_id']?.toString();
    if (id == null) return;
    try {
      final api = ref.read(apiClientProvider);
      final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await api.post('/day-status', body: {
        'member_id': id,
        'day_date': day,
        'status': 'not_traveling',
        'note': 'Marked not traveling today',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${m['display_name']} marked not traveling today — excluded from expected count',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'Could not update day status. Try again when online.',
      );
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? member}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _YatriEditorSheet(member: member),
    );
    if (saved == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(member == null ? 'Yatri added' : 'Yatri updated')),
        );
      }
    }
  }

  Future<void> _import() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post('/roster', body: {'csv': _csv.text});
      final n = (res['imported'] as num?)?.toInt() ?? 0;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              n == 0
                  ? 'No rows imported — each line needs at least phone,name (10-digit phone).'
                  : 'Imported $n member(s)',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Import failed. Check CSV format and try again.');
    }
  }

  Widget _tagChip(String tag, SharanamColors c, ThemeData theme) {
    final Color bg;
    final Color fg;
    if (tag.startsWith('Kanni')) {
      bg = c.gold.withValues(alpha: .18);
      fg = c.gold;
    } else if (tag.startsWith('Bell')) {
      bg = theme.colorScheme.primary.withValues(alpha: .14);
      fg = theme.colorScheme.primary;
    } else {
      bg = c.surfaceAlt;
      fg = theme.colorScheme.onSurface.withValues(alpha: .7);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        tag,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLeader = ref.watch(authProvider).user?['role'] == 'leader';
    final isHelper = ref.watch(authProvider).isLeaderOrVolunteer;
    final c = context.sharanam;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roster'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: isLeader
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add yatri'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 88),
          children: [
            ScreenHeader(
              title: 'Group members',
              subtitle: _loading ? 'Loading…' : '${_members.length} on roster',
            ),
            if (_error != null) ...[
              StatusBanner(kind: StatusBannerKind.danger, message: _error!),
              const SizedBox(height: 12),
            ],
            if (_loading)
              const SkeletonList()
            else if (_members.isEmpty)
              const EmptyState(
                icon: Icons.people_outline,
                message: 'No members yet',
                detail: 'Leader can add yatris or import a CSV roster.',
              )
            else
              ..._members.map((raw) {
                final m = Map<String, dynamic>.from(raw as Map);
                final phone = m['phone_e164']?.toString() ?? '';
                final name = m['display_name']?.toString() ?? '';
                final role = m['role']?.toString() ?? '';
                final tag = m['tag']?.toString();
                final photo = _photoUrl(m['photo_url']?.toString());
                return SectionCard(
                  onTap: isLeader ? () => _openEditor(member: m) : null,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: .12),
                        backgroundImage:
                            photo == null ? null : NetworkImage(photo),
                        child: photo != null
                            ? null
                            : Text(
                                name.isEmpty ? '?' : name[0].toUpperCase(),
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$role · $phone',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .6),
                              ),
                            ),
                            if (tag != null && tag.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              _tagChip(tag, c, theme),
                            ],
                          ],
                        ),
                      ),
                      if (isHelper)
                        IconButton(
                          tooltip: 'Not traveling today',
                          icon: Icon(Icons.event_busy, color: c.danger),
                          onPressed: () => _markNotTraveling(m),
                        ),
                      IconButton(
                        icon: Icon(Icons.call, color: c.success),
                        onPressed: phone.isEmpty
                            ? null
                            : () => launchUrl(Uri.parse('tel:$phone')),
                      ),
                    ],
                  ),
                );
              }),
            if (isLeader) ...[
              const SizedBox(height: 16),
              Text('Import CSV', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              SectionCard(
                child: Column(
                  children: [
                    TextField(
                      controller: _csv,
                      minLines: 4,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        labelText: 'phone,name,role,kanni,senior,years',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _import,
                      child: const Text('Import roster'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Leader-only add/edit form for a single yatri, including photo capture.
class _YatriEditorSheet extends ConsumerStatefulWidget {
  const _YatriEditorSheet({this.member});

  final Map<String, dynamic>? member;

  @override
  ConsumerState<_YatriEditorSheet> createState() => _YatriEditorSheetState();
}

class _YatriEditorSheetState extends ConsumerState<_YatriEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _years;
  String _role = 'swamy';
  Uint8List? _pickedBytes;
  String _pickedContentType = 'image/jpeg';
  String? _existingPhotoUrl;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.member != null;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    _name = TextEditingController(text: m?['display_name']?.toString() ?? '');
    _phone = TextEditingController(text: m?['phone_e164']?.toString() ?? '');
    final years = m?['yatra_years'];
    _years = TextEditingController(text: years == null ? '' : years.toString());
    _role = (m?['role']?.toString().isNotEmpty ?? false) ? m!['role'].toString() : 'swamy';
    final photo = m?['photo_url']?.toString();
    if (photo != null && photo.isNotEmpty) {
      _existingPhotoUrl =
          photo.startsWith('http') ? photo : '${ref.read(apiClientProvider).baseUrl}$photo';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _years.dispose();
    super.dispose();
  }

  String _contentTypeFor(XFile file) {
    final mime = file.mimeType;
    if (mime != null && mime.startsWith('image/')) return mime;
    final ext = file.name.toLowerCase().split('.').last;
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1280,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pickedBytes = bytes;
      _pickedContentType = _contentTypeFor(file);
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || phone.replaceAll(RegExp(r'[^0-9]'), '').length < 10) {
      setState(() => _error = 'Enter a name and a valid phone number.');
      return;
    }
    final years = int.tryParse(_years.text.trim());
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      String? photoKey;
      if (_pickedBytes != null) {
        final presign = await api.post('/roster/photo/presign', body: {
          'content_type': _pickedContentType,
        });
        final uploadUrl = presign['upload_url']?.toString() ?? '';
        photoKey = presign['key']?.toString();
        final rawHeaders = presign['headers'];
        final signedHeaders = <String, String>{};
        if (rawHeaders is Map) {
          rawHeaders.forEach((k, v) => signedHeaders[k.toString()] = v.toString());
        }
        final putContentType = signedHeaders['Content-Type'] ?? _pickedContentType;
        await api.putBinary(
          uploadUrl,
          bytes: _pickedBytes!,
          contentType: putContentType,
          signedHeaders: signedHeaders,
        );
      }

      final body = <String, dynamic>{
        'phone': phone,
        'display_name': name,
        'role': _role,
        'yatra_years': years,
        if (photoKey != null) 'photo_key': photoKey,
      };

      if (_isEdit) {
        final id = widget.member!['id']?.toString() ?? widget.member!['member_id']?.toString();
        await api.put('/roster/member/$id', body: body);
      } else {
        await api.post('/roster/member', body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save. Check the details and your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEdit ? 'Edit yatri' : 'Add yatri',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: .12),
                    backgroundImage: _pickedBytes != null
                        ? MemoryImage(_pickedBytes!)
                        : (_existingPhotoUrl != null
                            ? NetworkImage(_existingPhotoUrl!)
                            : null) as ImageProvider?,
                    child: (_pickedBytes == null && _existingPhotoUrl == null)
                        ? Icon(Icons.person,
                            size: 44, color: theme.colorScheme.primary)
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Material(
                      color: theme.colorScheme.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _saving ? null : _pickPhoto,
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.camera_alt,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Contact number',
                prefixIcon: Icon(Icons.call_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(value: 'swamy', child: Text('Swamy')),
                      DropdownMenuItem(
                          value: 'volunteer', child: Text('Volunteer')),
                      DropdownMenuItem(value: 'leader', child: Text('Leader')),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _role = v ?? 'swamy'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _years,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Years of yatra',
                      helperText: '1 = Kanni · 3 = Bell',
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              StatusBanner(kind: StatusBannerKind.danger, message: _error!),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Saving…' : 'Save yatri'),
            ),
          ],
        ),
      ),
    );
  }
}

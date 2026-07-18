import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';

class BroadcastScreen extends ConsumerStatefulWidget {
  const BroadcastScreen({super.key});

  @override
  ConsumerState<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends ConsumerState<BroadcastScreen> {
  List<dynamic> _items = [];
  String? _error;
  bool _urgent = false;
  bool _loading = true;
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final items = await api.get('/announcements') as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load broadcasts.';
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/announcements', body: {
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'priority': _urgent ? 'urgent' : 'info',
      });
      _title.clear();
      _body.clear();
      _urgent = false;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Broadcast sent')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not send broadcast. Try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend = ref.watch(authProvider).isLeaderOrVolunteer;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Broadcasts')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const ScreenHeader(
              title: 'Group announcements',
              subtitle: 'One-way updates from leaders',
            ),
            if (_error != null) ...[
              StatusBanner(kind: StatusBannerKind.danger, message: _error!),
              const SizedBox(height: 12),
            ],
            if (canSend) ...[
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Compose', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _title,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _body,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(labelText: 'Message'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Urgent'),
                      value: _urgent,
                      onChanged: (v) => setState(() => _urgent = v),
                    ),
                    FilledButton(
                      onPressed: _sending ? null : _send,
                      child: Text(_sending ? 'Sending…' : 'Send to group'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text('Recent', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_loading)
              const SkeletonList(itemCount: 3)
            else if (_items.isEmpty)
              const EmptyState(
                icon: Icons.campaign_outlined,
                message: 'No broadcasts yet',
                detail: 'Swamiye Sharanam — check back soon.',
              )
            else
              ..._items.map((raw) {
                final a = Map<String, dynamic>.from(raw as Map);
                final urgent = a['priority'] == 'urgent';
                return StatusBanner(
                  kind: urgent
                      ? StatusBannerKind.urgent
                      : StatusBannerKind.info,
                  title: a['title']?.toString(),
                  message: a['body']?.toString() ?? '',
                );
              }).expand((w) => [w, const SizedBox(height: 8)]),
          ],
        ),
      ),
    );
  }
}

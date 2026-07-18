import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    text: 'phone,name,role,kanni,senior\n'
        '9999000010,New Swamy,swamy,false,false\n',
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

  Future<void> _import() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post('/roster', body: {'csv': _csv.text});
      final n = res['imported'];
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $n member(s)')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Import failed. Check CSV format and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLeader = ref.watch(authProvider).user?['role'] == 'leader';
    final c = context.sharanam;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roster'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
                detail: 'Leader can import a CSV roster.',
              )
            else
              ..._members.map((raw) {
                final m = Map<String, dynamic>.from(raw as Map);
                final phone = m['phone_e164']?.toString() ?? '';
                final name = m['display_name']?.toString() ?? '';
                final role = m['role']?.toString() ?? '';
                return ListRowCard(
                  title: name,
                  subtitle: '$role · $phone',
                  leading: CircleAvatar(
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: .12),
                    child: Text(
                      name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (ref.watch(authProvider).isLeaderOrVolunteer)
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
                        labelText: 'phone,name,role,kanni,senior',
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

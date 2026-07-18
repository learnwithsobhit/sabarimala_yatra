import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';

class MalaRemindersScreen extends ConsumerStatefulWidget {
  const MalaRemindersScreen({super.key});

  @override
  ConsumerState<MalaRemindersScreen> createState() =>
      _MalaRemindersScreenState();
}

class _MalaRemindersScreenState extends ConsumerState<MalaRemindersScreen> {
  List<dynamic> _items = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/mala-reminders');
      setState(() {
        _items = res as List<dynamic>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addDefault() async {
    final auth = ref.read(authProvider);
    if (!auth.isLeaderOrVolunteer) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/mala-reminders', body: {
        'title': 'Mala removal',
        'body':
            'Remove the mala at the same place it was worn after returning home (or at Ravindra’s House on 20 Aug as planned).',
        'remind_on': '2026-08-20',
      });
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mala reminders'),
        actions: [
          if (auth.isLeaderOrVolunteer)
            IconButton(
              onPressed: _addDefault,
              icon: const Icon(Icons.add),
              tooltip: 'Add 20 Aug reminder',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const ScreenHeader(
            title: 'Post-trip mala',
            subtitle: 'Reminders for respectful mala removal',
          ),
          if (_error != null) ...[
            StatusBanner(kind: StatusBannerKind.danger, message: _error!),
            const SizedBox(height: 12),
          ],
          if (_loading)
            const SkeletonList()
          else if (_items.isEmpty)
            EmptyState(
              icon: Icons.auto_awesome_outlined,
              message: 'No reminders yet',
              detail: auth.isLeaderOrVolunteer
                  ? 'Tap + to add the 20 Aug mala removal note'
                  : 'Leader will post mala-removal reminders here',
            )
          else
            ..._items.map((raw) {
              final n = Map<String, dynamic>.from(raw as Map);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.spa_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  title: Text(n['title']?.toString() ?? ''),
                  subtitle: Text('${n['remind_on'] ?? ''}\n${n['body'] ?? ''}'),
                  isThreeLine: true,
                ),
              );
            }),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';

class DayNotesScreen extends ConsumerStatefulWidget {
  const DayNotesScreen({super.key});

  @override
  ConsumerState<DayNotesScreen> createState() => _DayNotesScreenState();
}

class _DayNotesScreenState extends ConsumerState<DayNotesScreen> {
  List<dynamic> _notes = [];
  String? _error;
  bool _loading = true;
  final _body = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
      final res = await api.get('/notes');
      setState(() {
        _notes = res as List<dynamic>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _post() async {
    final text = _body.text.trim();
    if (text.isEmpty) return;
    try {
      final api = ref.read(apiClientProvider);
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await api.post('/notes', body: {'day_date': today, 'body': text});
      _body.clear();
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Day notes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const ScreenHeader(
            title: 'Group notes',
            subtitle: 'Simple notes for each day of the yatra',
          ),
          if (_error != null) ...[
            StatusBanner(kind: StatusBannerKind.danger, message: _error!),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _body,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Add a note for today',
              hintText: 'Temple timing changed…',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _post, child: const Text('Post note')),
          const SizedBox(height: 16),
          if (_loading)
            const SkeletonList()
          else if (_notes.isEmpty)
            const EmptyState(
              icon: Icons.notes_outlined,
              message: 'No notes yet',
              detail: 'Share a short update for the group',
            )
          else
            ..._notes.map((raw) {
              final n = Map<String, dynamic>.from(raw as Map);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(n['body']?.toString() ?? ''),
                  subtitle: Text(
                    '${n['author_name'] ?? ''} · ${n['day_date'] ?? ''}',
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

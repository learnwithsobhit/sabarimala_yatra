import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';

class FoodScreen extends ConsumerStatefulWidget {
  const FoodScreen({super.key});

  @override
  ConsumerState<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends ConsumerState<FoodScreen> {
  Map<String, dynamic>? _session;
  Map<String, dynamic>? _board;
  String? _error;
  bool _busy = false;
  bool _loading = true;
  final _label = TextEditingController(text: 'Meal distribution');
  int _tab = 1;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final api = ref.read(apiClientProvider);
      final open = await api.get('/food/sessions/open');
      if (!mounted) return;
      if (open == null) {
        setState(() {
          _session = null;
          _board = null;
          _loading = false;
        });
        return;
      }
      final session = Map<String, dynamic>.from(open as Map);
      final board = await api.get('/food/sessions/${session['id']}/board')
          as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _session = session;
        _board = board;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load food session. Try again.';
        _loading = false;
      });
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/food/sessions', body: {
        'label': _label.text.trim(),
        'scope_kind': 'all',
      });
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not start food session.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mark({String? memberId, bool received = true}) async {
    if (_session == null) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/food/sessions/${_session!['id']}/mark', body: {
        if (memberId != null) 'member_id': memberId,
        'received': received,
      });
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not update mark. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_session == null) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/food/sessions/${_session!['id']}/stop');
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not close session.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final c = context.sharanam;
    final theme = Theme.of(context);
    final served = (_board?['served_count'] as num?)?.toInt() ?? 0;
    final expected = (_board?['expected_count'] as num?)?.toInt() ?? 0;
    final mine = _board?['my_received'] == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Food'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const ScreenHeader(
            title: 'Food distribution',
            subtitle: 'Train and bus meal ticks',
          ),
          if (_error != null) ...[
            StatusBanner(kind: StatusBannerKind.danger, message: _error!),
            const SizedBox(height: 12),
          ],
          if (_loading)
            const SkeletonList(itemCount: 3)
          else if (_session == null) ...[
            if (auth.isLeaderOrVolunteer) ...[
              const EmptyState(
                icon: Icons.restaurant_outlined,
                message: 'No open food session',
                detail: 'Start one for train or bus meals.',
              ),
              TextField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Meal label',
                  helperText: 'e.g. Train dinner 15 Aug · Bus 1 lunch',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _start,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start food distribution'),
              ),
            ] else
              const EmptyState(
                icon: Icons.restaurant_outlined,
                message: 'No open food session',
                detail: 'Wait for a leader or volunteer to start.',
              ),
          ] else ...[
            Center(
              child: Column(
                children: [
                  Text(
                    _session!['label']?.toString() ?? '',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  ProgressRing(
                    value: served,
                    total: expected,
                    label: 'Served',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (!mine)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: c.success,
                  foregroundColor: c.onSuccess,
                  minimumSize: const Size.fromHeight(64),
                ),
                onPressed: _busy ? null : () => _mark(),
                icon: const Icon(Icons.restaurant),
                label: const Text('I received food'),
              )
            else
              StatusBanner(
                kind: StatusBannerKind.success,
                title: 'You are marked as received',
                message: 'Swamiye Sharanam Ayyappa.',
              ),
            if (auth.isLeaderOrVolunteer) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : _stop,
                child: const Text('Close food session'),
              ),
            ],
            const SizedBox(height: 20),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text('Served $served')),
                ButtonSegment(
                  value: 1,
                  label: Text('Pending ${expected - served}'),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: 12),
            ...((_board?[(_tab == 0 ? 'served' : 'pending')] as List?) ?? [])
                .map((raw) {
              final m = Map<String, dynamic>.from(raw as Map);
              final name = m['display_name']?.toString() ?? '';
              return ListRowCard(
                title: name,
                subtitle: m['phone_e164']?.toString() ?? '',
                leading: CircleAvatar(
                  backgroundColor: (_tab == 0 ? c.success : c.gold)
                      .withValues(alpha: .14),
                  child: Text(
                    name.isEmpty ? '?' : name[0].toUpperCase(),
                    style: TextStyle(
                      color: _tab == 0 ? c.success : c.gold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                trailing: auth.isLeaderOrVolunteer && _tab == 1
                    ? IconButton(
                        tooltip: 'Mark served',
                        onPressed: () =>
                            _mark(memberId: m['member_id']?.toString()),
                        icon: Icon(Icons.restaurant, color: c.success),
                      )
                    : Icon(
                        _tab == 0 ? Icons.check_circle : Icons.schedule,
                        color: _tab == 0 ? c.success : c.gold,
                      ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

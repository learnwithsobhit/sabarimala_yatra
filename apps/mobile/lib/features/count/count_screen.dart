import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/present_sync.dart';
import '../../core/theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/progress_ring.dart';
import '../../core/widgets/status_banner.dart';
import '../../providers/auth_provider.dart';

class CountScreen extends ConsumerStatefulWidget {
  const CountScreen({super.key});

  @override
  ConsumerState<CountScreen> createState() => _CountScreenState();
}

class _CountScreenState extends ConsumerState<CountScreen> {
  Map<String, dynamic>? _session;
  Map<String, dynamic>? _board;
  String? _error;
  bool _busy = false;
  bool _localPresent = false;
  bool _offline = false;
  final _checkpoint = TextEditingController(text: 'Departure checkpoint');
  final _present = PresentSync();
  int _tab = 1; // default Not yet

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _checkpoint.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _error = null);
    try {
      final api = ref.read(apiClientProvider);
      await _present.flush(api);
      final open = await api.get('/count/sessions/open');
      if (!mounted) return;
      if (open == null) {
        await _present.cacheOpenSession(null);
        setState(() {
          _session = null;
          _board = null;
          _localPresent = false;
          _offline = false;
        });
        return;
      }
      final session = Map<String, dynamic>.from(open as Map);
      final board = await api.get('/count/sessions/${session['id']}/board')
          as Map<String, dynamic>;
      await _present.cacheOpenSession(session);
      if (!mounted) return;
      setState(() {
        _session = session;
        _board = board;
        _localPresent = board['my_status'] == 'present';
        _offline = false;
      });
    } catch (_) {
      final cached = await _present.cachedOpenSession();
      final queued = cached == null
          ? false
          : await _present.isQueued(cached['id'].toString());
      if (!mounted) return;
      setState(() {
        _session = cached;
        _offline = cached != null;
        _localPresent = queued || _localPresent;
        _error = cached == null
            ? 'Network issue — open Count once online so Present works offline.'
            : 'Offline — you can still mark Present; it will sync when connected.';
      });
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/count/sessions', body: {
        'checkpoint_label': _checkpoint.text.trim(),
        'scope_kind': 'all',
      });
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not start count. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markPresent() async {
    if (_session == null) return;
    final sessionId = _session!['id'].toString();
    setState(() {
      _busy = true;
      _localPresent = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    final api = ref.read(apiClientProvider);
    final result = await _present.markPresent(api, sessionId: sessionId);
    if (!mounted) return;
    if (result.queued) {
      setState(() {
        _error =
            'No network — marked Present locally. Will sync when you are back online.';
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Queued offline. Will sync when connected.'),
        ),
      );
      return;
    }
    await _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Marked Present. Swamiye Sharanam.')),
    );
  }

  Future<void> _stop({required bool force}) async {
    if (_session == null) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post(
        '/count/sessions/${_session!['id']}/stop',
        body: {
          'force': force,
          'ready_to_march_note': 'Ready to march',
        },
      );
      await _refresh();
    } catch (e) {
      final msg = e.toString();
      if (!force && msg.contains('force=true') && mounted) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Not everyone Present'),
            content: Text(msg),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep counting')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop anyway')),
            ],
          ),
        );
        if (ok == true) await _stop(force: true);
      } else {
        setState(() => _error = msg);
      }
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _helperMark(String memberId, String status) async {
    if (_session == null) return;
    final api = ref.read(apiClientProvider);
    await api.post('/count/sessions/${_session!['id']}/mark', body: {
      'member_id': memberId,
      'status': status,
    });
    await _refresh();
  }

  Future<void> _showHistory(bool helper) async {
    try {
      final api = ref.read(apiClientProvider);
      final raw = await api.get('/count/sessions/history') as List<dynamic>;
      if (!mounted) return;
      final history =
          raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Text(
                        'Count history',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: history.isEmpty
                      ? const EmptyState(
                          icon: Icons.history,
                          message: 'No count sessions yet',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: history.length,
                          itemBuilder: (context, i) {
                            final h = history[i];
                            final present =
                                (h['present_count'] as num?)?.toInt() ?? 0;
                            final excused =
                                (h['excused_count'] as num?)?.toInt() ?? 0;
                            final expected =
                                (h['expected_count'] as num?)?.toInt() ?? 0;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.fact_check_outlined),
                                title: Text(
                                  h['checkpoint_label']?.toString() ?? '',
                                ),
                                subtitle: Text(
                                  'Present $present · Excused $excused · Expected $expected',
                                ),
                                trailing: helper
                                    ? IconButton(
                                        tooltip: 'Copy paper roster CSV',
                                        icon: const Icon(Icons.download_outlined),
                                        onPressed: () async {
                                          final csv = await api.getText(
                                            '/count/sessions/${h['id']}/export.csv',
                                          );
                                          await Clipboard.setData(
                                            ClipboardData(text: csv),
                                          );
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(ctx)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Roster CSV copied — paste into Sheets or a file.',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load count history.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.sharanam;
    final auth = ref.watch(authProvider);
    final present = (_board?['present_count'] as num?)?.toInt() ?? 0;
    final expected = (_board?['expected_count'] as num?)?.toInt() ?? 0;
    final missing = ((_board?['missing'] as List?) ?? []).length;
    final excused = ((_board?['excused'] as List?) ?? []).length;
    final notYet = ((_board?['not_yet'] as List?) ?? []).length;
    final myStatus =
        _localPresent ? 'present' : _board?['my_status']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Head Count'),
        actions: [
          IconButton(
            tooltip: 'Count history',
            onPressed: () => _showHistory(auth.isLeaderOrVolunteer),
            icon: const Icon(Icons.history),
          ),
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (_error != null) ...[
            StatusBanner(
              kind: _offline
                  ? StatusBannerKind.info
                  : StatusBannerKind.danger,
              message: _error!,
            ),
            const SizedBox(height: 12),
          ],
          if (_session == null) ...[
            if (auth.isLeaderOrVolunteer) ...[
              EmptyState(
                icon: Icons.groups_outlined,
                message: 'No open count',
                detail: 'Start one before leaving a spot.',
              ),
              TextField(
                controller: _checkpoint,
                decoration:
                    const InputDecoration(labelText: 'Checkpoint / spot'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _start,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start count'),
              ),
            ] else
              const EmptyState(
                icon: Icons.groups_outlined,
                message: 'No open count',
                detail:
                    'Wait for the leader or volunteer to start counting.',
              ),
          ] else ...[
            Center(
              child: Column(
                children: [
                  Text(
                    _session!['checkpoint_label']?.toString() ?? '',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  ProgressRing(value: present, total: expected),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (myStatus != 'present')
              Semantics(
                button: true,
                label: 'I am Present',
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.success,
                    foregroundColor: c.onSuccess,
                    minimumSize: const Size.fromHeight(72),
                    textStyle: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: _busy ? null : _markPresent,
                  icon: const Icon(Icons.check_circle_outline, size: 28),
                  label: const Text('I am Present'),
                ),
              ).animate().fadeIn().scale(begin: const Offset(.98, .98))
            else
              StatusBanner(
                kind: StatusBannerKind.success,
                title: 'You are marked Present',
                message: 'Swamiye Sharanam Ayyappa.',
              )
                  .animate()
                  .fadeIn(duration: 250.ms)
                  .scale(begin: const Offset(.96, .96)),
            if (auth.isLeaderOrVolunteer) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _stop(force: false),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Stop count — ready to march'),
              ),
            ],
            const SizedBox(height: 20),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 0, label: Text('Present $present')),
                  ButtonSegment(value: 1, label: Text('Not yet $notYet')),
                  ButtonSegment(value: 2, label: Text('Missing $missing')),
                  ButtonSegment(value: 3, label: Text('Excused $excused')),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
            const SizedBox(height: 12),
            ..._listForTab(auth.isLeaderOrVolunteer),
          ],
        ],
      ),
    );
  }

  List<Widget> _listForTab(bool helper) {
    if (_board == null) return [];
    final c = context.sharanam;
    final theme = Theme.of(context);
    final key = switch (_tab) {
      0 => 'present',
      2 => 'missing',
      3 => 'excused',
      _ => 'not_yet',
    };
    final (statusColor, statusIcon) = switch (_tab) {
      0 => (c.success, Icons.check_circle),
      2 => (c.danger, Icons.person_off),
      3 => (c.gold, Icons.event_busy_outlined),
      _ => (theme.colorScheme.onSurface.withValues(alpha: .45), Icons.schedule),
    };
    final list = (_board![key] as List?) ?? [];
    if (list.isEmpty) {
      return [
        EmptyState(
          icon: statusIcon,
          message: switch (_tab) {
            0 => 'No one marked Present yet',
            2 => 'No one is missing',
            3 => 'No one is excused',
            _ => 'Everyone is accounted for',
          },
        ),
      ];
    }
    return list.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      final phone = m['phone_e164']?.toString() ?? '';
      final name = m['display_name']?.toString() ?? '';
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: CircleAvatar(
            backgroundColor: statusColor.withValues(alpha: .14),
            child: Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(phone),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              IconButton(
                tooltip: 'Call',
                onPressed: phone.isEmpty
                    ? null
                    : () => launchUrl(Uri.parse('tel:$phone')),
                icon: const Icon(Icons.call),
              ),
              if (helper && _tab != 0)
                IconButton(
                  tooltip: 'Mark present',
                  onPressed: () =>
                      _helperMark(m['member_id'].toString(), 'present'),
                  icon: Icon(Icons.check_circle_outline, color: c.success),
                ),
              if (helper && _tab == 1)
                IconButton(
                  tooltip: 'Mark missing',
                  onPressed: () =>
                      _helperMark(m['member_id'].toString(), 'missing'),
                  icon: Icon(Icons.person_off_outlined, color: c.danger),
                ),
              if (helper && (_tab == 1 || _tab == 2))
                IconButton(
                  tooltip: 'Mark excused',
                  onPressed: () =>
                      _helperMark(m['member_id'].toString(), 'excused'),
                  icon: Icon(Icons.event_busy_outlined, color: c.gold),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }
}

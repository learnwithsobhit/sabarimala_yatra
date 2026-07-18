import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/present_sync.dart';
import '../../core/theme.dart';
import '../../core/trip_pack_store.dart';
import '../../core/widgets/feature_tile.dart';
import '../../core/widgets/pass_card.dart';
import '../../core/widgets/status_banner.dart';
import '../../providers/auth_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Map<String, dynamic>? _now;
  Map<String, dynamic>? _assignment;
  String? _error;
  String? _packNote;
  bool _loading = true;
  bool _fromCache = false;
  bool _localPresent = false;
  bool _markingPresent = false;
  final _pack = TripPackStore();
  final _present = PresentSync();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _fromCache = false;
    });
    try {
      final api = ref.read(apiClientProvider);
      final auth = ref.read(authProvider);
      final tripId = auth.user?['trip_id'];
      final now = await api.get('/home/now') as Map<String, dynamic>;
      final assignment = await api.get('/assignments/me');
      final itinerary = tripId == null
          ? <dynamic>[]
          : await api.get('/trips/$tripId/itinerary') as List<dynamic>;
      final announcements = await api.get('/announcements') as List<dynamic>;
      await _present.flush(api);

      final assignmentMap =
          assignment is Map<String, dynamic> ? assignment : null;
      final openCountId = now['open_count_session_id']?.toString();
      if (openCountId != null && openCountId.isNotEmpty) {
        await _present.cacheOpenSession({'id': openCountId});
      } else {
        await _present.cacheOpenSession(null);
      }
      await _pack.save({
        'now': now,
        'assignment': assignmentMap,
        'itinerary': itinerary,
        'announcements': announcements,
      });
      final synced = await _pack.syncedAt();
      final queued = openCountId == null
          ? false
          : await _present.isQueued(openCountId);

      if (!mounted) return;
      setState(() {
        _now = now;
        _assignment = assignmentMap;
        _localPresent = queued;
        _loading = false;
        _fromCache = false;
        _packNote =
            synced == null ? null : 'Trip pack saved ${synced.toLocal()}';
      });
    } catch (e) {
      final cached = await _pack.load();
      if (!mounted) return;
      if (cached != null) {
        final openCountId = cached['open_count_session_id']?.toString() ??
            (cached['now'] as Map?)?['open_count_session_id']?.toString();
        final queued = openCountId == null
            ? false
            : await _present.isQueued(openCountId);
        setState(() {
          _now = cached['now'] as Map<String, dynamic>?;
          _assignment = cached['assignment'] as Map<String, dynamic>?;
          _localPresent = queued;
          _error = 'Offline — showing saved trip pack.';
          _fromCache = true;
          _loading = false;
          _packNote = 'Using offline pack';
        });
      } else {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _markPresentFromHome(String sessionId) async {
    setState(() {
      _markingPresent = true;
      _localPresent = true;
    });
    HapticFeedback.mediumImpact();
    final api = ref.read(apiClientProvider);
    final result = await _present.markPresent(api, sessionId: sessionId);
    if (!mounted) return;
    setState(() => _markingPresent = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.queued
              ? 'Queued offline. Will sync when connected.'
              : 'Marked Present. Swamiye Sharanam.',
        ),
      ),
    );
    if (!result.queued) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.sharanam;
    final auth = ref.watch(authProvider);
    final openCountId = _now?['open_count_session_id'];
    final next = _now?['next_stop'] as Map<String, dynamic>?;
    final ann = _now?['latest_announcement'] as Map<String, dynamic>?;
    final trip = _now?['trip'] as Map<String, dynamic>?;
    final role = auth.user?['role']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Swamy Sharanam'),
        actions: [
          IconButton(
            tooltip: 'If you are lost — SOS',
            onPressed: () => context.go('/more/lost'),
            icon: Icon(Icons.sos, color: c.danger),
          ),
          IconButton(
            tooltip: 'Refresh / save trip pack',
            onPressed: _load,
            icon: const Icon(Icons.cloud_download_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await ref.read(authProvider).logout();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (_error != null) ...[
                    StatusBanner(
                      kind: _fromCache
                          ? StatusBannerKind.offline
                          : StatusBannerKind.danger,
                      message: _error!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    'Swamiye Sharanam Ayyappa',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    trip?['title']?.toString() ?? 'Yatra',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (openCountId != null) ...[
                    if (_localPresent)
                      StatusBanner(
                        kind: StatusBannerKind.success,
                        title: 'You are marked Present',
                        message: _fromCache
                            ? 'Queued or saved offline — open Count for the live board.'
                            : 'Swamiye Sharanam Ayyappa.',
                      )
                    else
                      Semantics(
                        button: true,
                        label: 'I am Present',
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: c.success,
                            foregroundColor: c.onSuccess,
                            minimumSize: const Size.fromHeight(64),
                          ),
                          onPressed: _markingPresent
                              ? null
                              : () => _markPresentFromHome(
                                    openCountId.toString(),
                                  ),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 26,
                          ),
                          label: const Text('I am Present'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => context.go('/count'),
                      child: const Text('Open live count board'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  PassCard(
                    memberName:
                        auth.user?['display_name']?.toString() ?? 'Swamy',
                    role: role == null || role.isEmpty
                        ? null
                        : role[0].toUpperCase() + role.substring(1),
                    nextStopTitle: next?['title']?.toString(),
                    nextStopPlace: next?['place_name']?.toString(),
                    rows: [
                      PassRow(
                        icon: Icons.directions_bus_outlined,
                        label: 'Bus',
                        value:
                            _assignment?['vehicle_label']?.toString() ?? '—',
                      ),
                      PassRow(
                        icon: Icons.hotel_outlined,
                        label: 'Room',
                        value: [
                          _assignment?['hotel_name'],
                          _assignment?['room_label'],
                        ].whereType<Object>().join(' ').trim().isEmpty
                            ? '—'
                            : [
                                _assignment?['hotel_name'],
                                _assignment?['room_label'],
                              ].whereType<Object>().join(' '),
                      ),
                      PassRow(
                        icon: Icons.train_outlined,
                        label: 'Train',
                        value: [
                          _assignment?['train_number'],
                          _assignment?['coach'],
                          _assignment?['berth'],
                        ].whereType<Object>().join(' ').trim().isEmpty
                            ? '—'
                            : [
                                _assignment?['train_number'],
                                _assignment?['coach'],
                                _assignment?['berth'],
                              ].whereType<Object>().join(' '),
                      ),
                    ],
                  ),
                  if (ann != null) ...[
                    const SizedBox(height: 16),
                    StatusBanner(
                      kind: ann['priority'] == 'urgent'
                          ? StatusBannerKind.urgent
                          : StatusBannerKind.info,
                      title: ann['title']?.toString(),
                      message: ann['body']?.toString() ?? '',
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text('Quick access', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.55,
                    children: [
                      FeatureTile(
                        icon: Icons.route_outlined,
                        label: 'Itinerary',
                        subtitle: 'Full day plan',
                        onTap: () => context.go('/itinerary'),
                      ),
                      FeatureTile(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Expenses',
                        subtitle: 'Track & split',
                        color: c.success,
                        onTap: () => context.go('/more/expenses'),
                      ),
                      FeatureTile(
                        icon: Icons.photo_library_outlined,
                        label: 'Memories',
                        subtitle: 'Yatra photos',
                        color: const Color(0xFF7C3AED),
                        onTap: () => context.go('/more/memories'),
                      ),
                      FeatureTile(
                        icon: Icons.backpack_outlined,
                        label: 'Packing',
                        subtitle: 'Checklist',
                        color: const Color(0xFF0369A1),
                        onTap: () => context.go('/more/packing'),
                      ),
                    ],
                  ),
                  if (_packNote != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _packNote!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/trip_pack_store.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';

class ItineraryScreen extends ConsumerStatefulWidget {
  const ItineraryScreen({super.key});

  @override
  ConsumerState<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends ConsumerState<ItineraryScreen> {
  List<dynamic> _stops = [];
  String? _error;
  bool _offline = false;
  bool _loading = true;
  final _scroll = ScrollController();
  final _dayFmt = DateFormat('EEE, MMM d');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authProvider);
      final tripId = auth.user?['trip_id'];
      if (tripId == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Trip not found. Sign in again.';
        });
        return;
      }
      final api = ref.read(apiClientProvider);
      final stops = await api.get('/trips/$tripId/itinerary') as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _stops = stops;
        _offline = false;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
    } catch (_) {
      final pack = await TripPackStore().load();
      final cached = pack?['itinerary'];
      if (!mounted) return;
      if (cached is List && cached.isNotEmpty) {
        setState(() {
          _stops = cached;
          _offline = true;
          _error = 'Offline — showing saved itinerary';
          _loading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
      } else {
        setState(() {
          _error = 'Could not load plan. Check network and try again.';
          _loading = false;
        });
      }
    }
  }

  int? _todayIndex() {
    final today = DateTime.now();
    for (var i = 0; i < _stops.length; i++) {
      final s = Map<String, dynamic>.from(_stops[i] as Map);
      final raw = s['day_date']?.toString();
      if (raw == null) continue;
      final d = DateTime.tryParse(raw);
      if (d != null &&
          d.year == today.year &&
          d.month == today.month &&
          d.day == today.day) {
        return i;
      }
    }
    return null;
  }

  void _scrollToToday() {
    final idx = _todayIndex();
    if (idx == null || !_scroll.hasClients) return;
    _scroll.animateTo(
      (idx * 120).toDouble(),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  String _formatDay(String? raw) {
    if (raw == null) return '';
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    return _dayFmt.format(d);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sharanam;
    final theme = Theme.of(context);
    final todayIdx = _todayIndex();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const ScreenHeader(
              title: 'Yatra itinerary',
              subtitle: 'Day by day — Aug 15–20',
            ),
            if (_error != null) ...[
              StatusBanner(
                kind: _offline
                    ? StatusBannerKind.offline
                    : StatusBannerKind.danger,
                message: _error!,
              ),
              const SizedBox(height: 12),
            ],
            if (_loading)
              const SkeletonList(itemCount: 5)
            else if (_stops.isEmpty)
              const EmptyState(
                icon: Icons.route_outlined,
                message: 'No itinerary yet',
                detail: 'Ask the leader to publish the day plan.',
              )
            else
              ...List.generate(_stops.length, (i) {
                final s = Map<String, dynamic>.from(_stops[i] as Map);
                final isToday = i == todayIdx;
                final isLast = i == _stops.length - 1;
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 28,
                        child: Column(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: isToday
                                    ? theme.colorScheme.primary
                                    : c.gold,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.surface,
                                  width: 2,
                                ),
                              ),
                            ),
                            if (!isLast)
                              Expanded(
                                child: Container(
                                  width: 2,
                                  color: c.border,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SectionCard(
                          color: isToday
                              ? theme.colorScheme.primaryContainer
                                  .withValues(alpha: .45)
                              : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _formatDay(s['day_date']?.toString()),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (isToday) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'TODAY',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: theme.colorScheme.onPrimary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                s['title']?.toString() ?? '',
                                style: theme.textTheme.titleMedium,
                              ),
                              if (s['place_name'] != null)
                                Text(s['place_name'].toString()),
                              if (s['notes'] != null) ...[
                                const SizedBox(height: 8),
                                Text(s['notes'].toString()),
                              ],
                              if (s['lost_person_tip'] != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'If lost: ${s['lost_person_tip']}',
                                  style: TextStyle(
                                    color: c.danger,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

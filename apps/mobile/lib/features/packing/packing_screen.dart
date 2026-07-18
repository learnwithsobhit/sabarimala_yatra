import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/trip_pack_store.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';

class PackingScreen extends ConsumerStatefulWidget {
  const PackingScreen({super.key});

  @override
  ConsumerState<PackingScreen> createState() => _PackingScreenState();
}

class _PackingScreenState extends ConsumerState<PackingScreen> {
  List<Map<String, dynamic>> _items = [];
  int _checked = 0;
  int _total = 0;
  String? _error;
  bool _offline = false;
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
      final res = await api.get('/packing/me') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _items = ((res['items'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _checked = res['checked'] as int? ?? 0;
        _total = res['total'] as int? ?? 0;
        _offline = false;
        _loading = false;
      });
      final pack = await TripPackStore().load() ?? {};
      pack['packing'] = res;
      await TripPackStore().save(pack);
    } catch (_) {
      final pack = await TripPackStore().load();
      final cached = pack?['packing'] as Map<String, dynamic>?;
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _items = ((cached['items'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _checked = cached['checked'] as int? ?? 0;
          _total = cached['total'] as int? ?? 0;
          _offline = true;
          _error = 'Offline — showing saved packing list';
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Could not load packing list.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggle(int index) async {
    if (index < 0 || index >= _items.length) return;
    final item = Map<String, dynamic>.from(_items[index]);
    final id = item['id']?.toString();
    if (id == null) return;
    final next = !(item['checked'] == true);
    setState(() {
      _items[index] = {...item, 'checked': next};
      _checked += next ? 1 : -1;
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.put('/packing/check', body: {
        'item_id': id,
        'checked': next,
      });
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items[index] = {...item, 'checked': !next};
        _checked += next ? -1 : 1;
        _error = 'Could not save — try again when online.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sharanam;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Packing'),
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
              title: 'Packing checklist',
              subtitle: '$_checked / $_total packed',
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
              const SkeletonList()
            else if (_items.isEmpty)
              const EmptyState(
                icon: Icons.backpack_outlined,
                message: 'No packing items',
              )
            else ...[
              LinearProgressIndicator(
                value: _total == 0 ? 0 : _checked / _total,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
                color: c.success,
                backgroundColor: c.surfaceAlt,
              ),
              const SizedBox(height: 16),
              ...List.generate(_items.length, (i) {
                final item = _items[i];
                final checked = item['checked'] == true;
                return SectionCard(
                  onTap: () => _toggle(i),
                  child: Row(
                    children: [
                      Icon(
                        checked
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: checked
                            ? c.success
                            : theme.colorScheme.onSurface.withValues(alpha: .4),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title']?.toString() ?? '',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                decoration: checked
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (item['quantity_hint'] != null)
                              Text(
                                item['quantity_hint'].toString(),
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

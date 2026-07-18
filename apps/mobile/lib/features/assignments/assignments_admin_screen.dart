import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';

class AssignmentsAdminScreen extends ConsumerStatefulWidget {
  const AssignmentsAdminScreen({super.key});

  @override
  ConsumerState<AssignmentsAdminScreen> createState() =>
      _AssignmentsAdminScreenState();
}

class _AssignmentsAdminScreenState
    extends ConsumerState<AssignmentsAdminScreen> {
  List<dynamic> _assignments = [];
  Map<String, dynamic>? _catalog;
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
      final assignments = await api.get('/assignments') as List<dynamic>;
      final catalog = await api.get('/assignments/catalog') as Map<String, dynamic>;
      setState(() {
        _assignments = assignments;
        _catalog = catalog;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load assignments.';
        _loading = false;
      });
    }
  }

  Future<void> _seed() async {
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/assignments/seed-defaults');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Default buses, rooms & coaches ready')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not seed defaults.');
    }
  }

  Future<void> _editMember(Map<String, dynamic> row) async {
    final catalog = _catalog;
    if (catalog == null) return;

    final vehicles = (catalog['vehicles'] as List?) ?? [];
    final rooms = (catalog['rooms'] as List?) ?? [];
    final berths = (catalog['train_berths'] as List?) ?? [];

    String? vehicleId;
    String? roomId;
    String? berthId;
    final seat = TextEditingController(text: row['seat_label']?.toString() ?? '');

    // Preselect by label match
    for (final v in vehicles) {
      final m = Map<String, dynamic>.from(v as Map);
      if (m['label'] == row['vehicle_label']) vehicleId = m['id']?.toString();
    }
    for (final r in rooms) {
      final m = Map<String, dynamic>.from(r as Map);
      if (m['room_label'] == row['room_label'] &&
          m['hotel_name'] == row['hotel_name']) {
        roomId = m['id']?.toString();
      }
    }
    for (final b in berths) {
      final m = Map<String, dynamic>.from(b as Map);
      if (m['coach'] == row['coach'] &&
          m['train_number'] == row['train_number']) {
        berthId = m['id']?.toString();
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(row['display_name']?.toString() ?? 'Assign'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: vehicleId,
                  decoration: const InputDecoration(labelText: 'Bus'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    ...vehicles.map((v) {
                      final m = Map<String, dynamic>.from(v as Map);
                      return DropdownMenuItem(
                        value: m['id']?.toString(),
                        child: Text(m['label']?.toString() ?? ''),
                      );
                    }),
                  ],
                  onChanged: (v) => setLocal(() => vehicleId = v),
                ),
                TextField(
                  controller: seat,
                  decoration: const InputDecoration(labelText: 'Seat (optional)'),
                ),
                DropdownButtonFormField<String?>(
                  initialValue: roomId,
                  decoration: const InputDecoration(labelText: 'Room'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    ...rooms.map((r) {
                      final m = Map<String, dynamic>.from(r as Map);
                      return DropdownMenuItem(
                        value: m['id']?.toString(),
                        child: Text(
                          '${m['hotel_name']} · ${m['room_label']}',
                        ),
                      );
                    }),
                  ],
                  onChanged: (v) => setLocal(() => roomId = v),
                ),
                DropdownButtonFormField<String?>(
                  initialValue: berthId,
                  decoration: const InputDecoration(labelText: 'Train coach'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    ...berths.map((b) {
                      final m = Map<String, dynamic>.from(b as Map);
                      return DropdownMenuItem(
                        value: m['id']?.toString(),
                        child: Text(
                          '${m['train_number']} ${m['coach']} (${m['direction']})',
                        ),
                      );
                    }),
                  ],
                  onChanged: (v) => setLocal(() => berthId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok != true) {
      seat.dispose();
      return;
    }
    final seatLabel = seat.text.trim();
    seat.dispose();
    try {
      final api = ref.read(apiClientProvider);
      await api.put('/assignments', body: {
        'member_id': row['member_id'],
        'vehicle_id': vehicleId,
        'seat_label': seatLabel.isEmpty ? null : seatLabel,
        'room_id': roomId,
        'train_berth_id': berthId,
      });
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not save assignment.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.sharanam;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assignments'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          TextButton(onPressed: _seed, child: const Text('Seed')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const ScreenHeader(
              title: 'Bus · room · coach',
              subtitle:
                  'Tap a Swamy to assign. Seed creates Bus 1–3, hotels & train coaches.',
            ),
            if (_error != null) ...[
              StatusBanner(kind: StatusBannerKind.danger, message: _error!),
              const SizedBox(height: 12),
            ],
            if (_loading)
              const SkeletonList()
            else if (_assignments.isEmpty)
              const EmptyState(
                icon: Icons.directions_bus_outlined,
                message: 'No members to assign',
                detail: 'Import the roster first, then seed defaults.',
              )
            else
              ..._assignments.map((raw) {
                final row = Map<String, dynamic>.from(raw as Map);
                final name = row['display_name']?.toString() ?? '';
                final subtitle = [
                  if (row['vehicle_label'] != null)
                    'Bus ${row['vehicle_label']}',
                  if (row['hotel_name'] != null)
                    '${row['hotel_name']} ${row['room_label'] ?? ''}',
                  if (row['train_number'] != null)
                    '${row['train_number']} ${row['coach'] ?? ''}',
                ]
                    .where((e) => e.trim().isNotEmpty)
                    .join(' · ')
                    .ifEmpty('Not assigned');
                return ListRowCard(
                  title: name,
                  subtitle: subtitle,
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
                  trailing: Icon(Icons.chevron_right, color: c.gold),
                  onTap: () => _editMember(row),
                );
              }),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

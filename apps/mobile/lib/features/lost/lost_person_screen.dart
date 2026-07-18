import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';

class LostPersonScreen extends ConsumerStatefulWidget {
  const LostPersonScreen({super.key});

  @override
  ConsumerState<LostPersonScreen> createState() => _LostPersonScreenState();
}

class _LostPersonScreenState extends ConsumerState<LostPersonScreen> {
  List<dynamic> _helpers = [];
  String? _error;
  bool _sending = false;

  static const _spots = [
    (
      'Guruvayur',
      'Wait in front of the temple’s main door for a team member.'
    ),
    (
      'Thrissur',
      'Wait at the main entrance of Vadakkunnathan Temple.'
    ),
    (
      'Chottanikkara',
      'Wait at the entrance of the main temple (upper temple).'
    ),
    (
      'Pamba (going up)',
      'Wait near the starting point of the steps at Pamba Ganapathy, just before Virtual Q / Aadhaar check. Network is poor — BSNL usually works.'
    ),
    (
      'Pamba (returning)',
      'Wait near the Indian Oil petrol bunk.'
    ),
    (
      'Sabarimala',
      'Wait in front of the Holy 18 Steps if below the main temple, or near the Melshanthi room if on top.'
    ),
    (
      'Other temples',
      'Wait at the main entrance of the temple.'
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadHelpers();
  }

  Future<void> _loadHelpers() async {
    try {
      final api = ref.read(apiClientProvider);
      final roster = await api.get('/roster') as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _helpers = roster.where((raw) {
          final m = Map<String, dynamic>.from(raw as Map);
          final role = m['role']?.toString();
          return role == 'leader' || role == 'volunteer';
        }).toList();
      });
    } catch (_) {
      // Offline — tips still useful
    }
  }

  Future<void> _broadcastLost(String spot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send SOS?'),
        content: Text(
          'This sends an urgent alert to the whole group that you are waiting at $spot.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/announcements/sos', body: {'spot': spot});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Urgent SOS sent — waiting at $spot')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Could not send SOS offline. Stay at the rendezvous and call a helper.',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sharanam;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('If you are lost')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const ScreenHeader(
            title: 'Stay calm',
            subtitle: 'Wait at the designated place. Swamiye Sharanam Ayyappa.',
          ),
          if (_error != null) ...[
            StatusBanner(kind: StatusBannerKind.danger, message: _error!),
            const SizedBox(height: 12),
          ],
          StatusBanner(
            kind: StatusBannerKind.info,
            title: 'Do not wander',
            message:
                'Stay put, send SOS if needed, and call a helper below.',
          ),
          const SizedBox(height: 16),
          ..._spots.map(
            (s) => SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.$1, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(s.$2),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: _sending ? null : () => _broadcastLost(s.$1),
                      child: const Text('I am here — SOS'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Call helpers', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_helpers.isEmpty)
            const EmptyState(
              icon: Icons.call_outlined,
              message: 'Helpers unavailable offline',
              detail: 'Open when online to load leader/volunteer numbers.',
            )
          else
            ..._helpers.map((raw) {
              final m = Map<String, dynamic>.from(raw as Map);
              final phone = m['phone_e164']?.toString() ?? '';
              final name = m['display_name']?.toString() ?? '';
              return ListRowCard(
                title: name,
                subtitle: '${m['role']} · $phone',
                leading: CircleAvatar(
                  backgroundColor: c.danger.withValues(alpha: .12),
                  child: Icon(Icons.person, color: c.danger),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.call, size: 28, color: c.success),
                  onPressed: phone.isEmpty
                      ? null
                      : () => launchUrl(Uri.parse('tel:$phone')),
                ),
              );
            }),
        ],
      ),
    );
  }
}

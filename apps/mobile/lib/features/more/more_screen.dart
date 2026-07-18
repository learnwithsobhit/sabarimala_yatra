import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final c = context.sharanam;

    final tiles = <Widget>[
      FeatureTile(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Expenses',
        subtitle: 'Balances & ledger',
        color: c.success,
        onTap: () => context.go('/more/expenses'),
      ),
      FeatureTile(
        icon: Icons.chat_bubble_outline,
        label: 'Ask guide',
        subtitle: 'Itinerary FAQ',
        onTap: () => context.go('/more/chat'),
      ),
      FeatureTile(
        icon: Icons.sos_outlined,
        label: 'If lost',
        subtitle: 'Rendezvous + SOS',
        color: c.danger,
        onTap: () => context.go('/more/lost'),
      ),
      FeatureTile(
        icon: Icons.restaurant_outlined,
        label: 'Food',
        subtitle: 'Meal ticks',
        color: c.urgentContainer,
        onTap: () => context.go('/more/food'),
      ),
      FeatureTile(
        icon: Icons.checklist_outlined,
        label: 'Packing',
        subtitle: 'Checklist',
        color: Theme.of(context).colorScheme.primary,
        onTap: () => context.go('/more/packing'),
      ),
      FeatureTile(
        icon: Icons.photo_library_outlined,
        label: 'Memories',
        subtitle: 'Yatra photos',
        color: c.gold,
        onTap: () => context.go('/more/memories'),
      ),
      FeatureTile(
        icon: Icons.notes_outlined,
        label: 'Day notes',
        subtitle: 'Group updates',
        color: c.success,
        onTap: () => context.go('/more/notes'),
      ),
      FeatureTile(
        icon: Icons.spa_outlined,
        label: 'Mala',
        subtitle: 'Removal reminders',
        onTap: () => context.go('/more/mala'),
      ),
      FeatureTile(
        icon: Icons.rate_review_outlined,
        label: 'Feedback',
        subtitle: 'Lessons next year',
        onTap: () => context.go('/more/feedback'),
      ),
      FeatureTile(
        icon: Icons.people_outline,
        label: 'Roster',
        subtitle: 'Group members',
        onTap: () => context.go('/more/roster'),
      ),
      if (auth.isLeaderOrVolunteer) ...[
        FeatureTile(
          icon: Icons.directions_bus_outlined,
          label: 'Assignments',
          subtitle: 'Bus, room, train',
          onTap: () => context.go('/more/assignments'),
        ),
        FeatureTile(
          icon: Icons.campaign_outlined,
          label: 'Broadcasts',
          subtitle: 'Message the group',
          color: Theme.of(context).colorScheme.primary,
          onTap: () => context.go('/more/broadcasts'),
        ),
      ],
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const ScreenHeader(
            title: 'Tools & services',
            subtitle: 'Everything for the yatra in one place',
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.45,
            children: tiles,
          ),
        ],
      ),
    );
  }
}

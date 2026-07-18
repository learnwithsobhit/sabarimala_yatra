import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/announcements/broadcast_screen.dart';
import 'features/assignments/assignments_admin_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/count/count_screen.dart';
import 'features/expenses/expenses_screen.dart';
import 'features/food/food_screen.dart';
import 'features/home/home_screen.dart';
import 'features/itinerary/itinerary_screen.dart';
import 'features/lost/lost_person_screen.dart';
import 'features/memories/memories_screen.dart';
import 'features/more/more_screen.dart';
import 'features/packing/packing_screen.dart';
import 'features/roster/roster_screen.dart';
import 'providers/auth_provider.dart';
import 'shell.dart';

/// GoRouter must be created once. Recreating it on every auth.busy notify
/// remounts LoginScreen and makes Send OTP look broken.
final goRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.read(authProvider);

  final router = GoRouter(
    initialLocation: '/home',
    refreshListenable: auth,
    redirect: (context, state) {
      // Always read latest auth; do not close over a stale rebuild snapshot.
      final loggedIn = auth.token != null;
      final loggingIn = state.matchedLocation == '/login';
      if (!loggedIn && !loggingIn) return '/login';
      if (loggedIn && loggingIn) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/count', builder: (_, __) => const CountScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/itinerary',
                builder: (_, __) => const ItineraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/more',
                builder: (_, __) => const MoreScreen(),
                routes: [
                  GoRoute(
                    path: 'expenses',
                    builder: (_, __) => const ExpensesScreen(),
                  ),
                  GoRoute(
                    path: 'chat',
                    builder: (_, __) => const ChatScreen(),
                  ),
                  GoRoute(
                    path: 'assignments',
                    builder: (_, __) => const AssignmentsAdminScreen(),
                  ),
                  GoRoute(
                    path: 'broadcasts',
                    builder: (_, __) => const BroadcastScreen(),
                  ),
                  GoRoute(
                    path: 'roster',
                    builder: (_, __) => const RosterScreen(),
                  ),
                  GoRoute(
                    path: 'lost',
                    builder: (_, __) => const LostPersonScreen(),
                  ),
                  GoRoute(
                    path: 'food',
                    builder: (_, __) => const FoodScreen(),
                  ),
                  GoRoute(
                    path: 'packing',
                    builder: (_, __) => const PackingScreen(),
                  ),
                  GoRoute(
                    path: 'memories',
                    builder: (_, __) => const MemoriesScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});

class SwamySharanamApp extends ConsumerWidget {
  const SwamySharanamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'Swamy Sharanam',
      theme: buildSharanamTheme(),
      darkTheme: buildSharanamDarkTheme(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

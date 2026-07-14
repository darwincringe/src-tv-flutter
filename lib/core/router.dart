import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/details/details_screen.dart';
import '../ui/home/home_screen.dart';
import '../ui/movies/movies_screen.dart';
import '../ui/player/player_args.dart';
import '../ui/player/player_screen.dart';
import '../ui/search/search_screen.dart';
import '../ui/series/series_screen.dart';
import '../ui/settings/settings_screen.dart';
import '../ui/shell/app_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Branch order matches the nav rail: Search, Home, Movies, TV Series,
/// Settings. The app opens on Home via [initialLocation]. Details and the
/// player are full-screen routes on the root navigator.
final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: '/search', builder: (c, s) => const SearchScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/home', builder: (c, s) => const HomeScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/movies', builder: (c, s) => const MoviesScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/series', builder: (c, s) => const SeriesScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen())],
        ),
      ],
    ),
    GoRoute(
      path: '/details/:type/:id',
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => DetailsScreen(
        mediaType: s.pathParameters['type']!,
        id: int.parse(s.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/player',
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => PlayerScreen(args: s.extra as PlayerArgs),
    ),
  ],
);

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/auth/auth_service.dart';
import '../data/store/library_store.dart';
import '../data/store/watch_progress.dart';
import '../ui/auth/welcome_screen.dart';
import '../ui/details/details_screen.dart';
import '../ui/home/home_screen.dart';
import '../ui/library/library_screen.dart';
import '../ui/movies/movies_screen.dart';
import '../ui/player/player_args.dart';
import '../ui/player/player_view.dart';
import '../ui/player/youtube_trailer_screen.dart';
import '../ui/search/search_screen.dart';
import '../ui/series/series_screen.dart';
import '../ui/settings/settings_screen.dart';
import '../ui/shell/app_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Branch order matches the nav rail: Search, Home, Movies, TV Series, Library,
/// Settings. The app opens on Home via [initialLocation]. Details and the
/// player are full-screen routes on the root navigator.
final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/home',
  // First-run gate: on a fresh install (not signed in, never onboarded, and no
  // local data yet) send the user to /welcome to register/login or skip. Once
  // they sign in, skip, or have any local data, the gate no longer applies.
  redirect: (context, state) {
    final gate = !AuthService.isSignedIn &&
        !AuthService.onboardingDone &&
        WatchProgressStore.all().isEmpty &&
        LibraryStore.all().isEmpty;
    final loc = state.matchedLocation;
    final atWelcome = loc == '/welcome';
    // Let a shared deep link (a specific title or video) through the first-run
    // gate so the link actually opens what it points at.
    final isDeepLink = loc.startsWith('/watch') || loc.startsWith('/details');
    if (gate && !atWelcome && !isDeepLink) return '/welcome';
    if (!gate && atWelcome) return '/home';
    return null;
  },
  routes: [
    GoRoute(
      path: '/welcome',
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const WelcomeScreen(),
    ),
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
          routes: [GoRoute(path: '/library', builder: (c, s) => const LibraryScreen())],
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
    // Path-based so the URL identifies the video (shareable + survives a
    // refresh): /watch/movie/<id> or /watch/tv/<id>?s=<season>&e=<episode>.
    // `extra` (when navigating in-app) only carries the backdrop for an instant
    // loading image; everything needed to play comes from the path/query.
    GoRoute(
      path: '/watch/:type/:id',
      parentNavigatorKey: rootNavigatorKey,
      redirect: (c, s) {
        final type = s.pathParameters['type'];
        final id = int.tryParse(s.pathParameters['id'] ?? '');
        if (id == null || (type != 'movie' && type != 'tv')) return '/home';
        return null;
      },
      builder: (c, s) {
        final type = s.pathParameters['type']!;
        final id = int.parse(s.pathParameters['id']!);
        final q = s.uri.queryParameters;
        final extra = s.extra;
        return PlayerScreen(
          args: PlayerArgs.stream(
            tmdbId: id,
            type: type,
            season: type == 'tv' ? int.tryParse(q['s'] ?? '') : null,
            episode: type == 'tv' ? int.tryParse(q['e'] ?? '') : null,
            backdropPath: extra is PlayerArgs ? extra.backdropPath : null,
          ),
        );
      },
    ),
    GoRoute(
      path: '/trailer/:key',
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => YoutubeTrailerScreen(videoId: s.pathParameters['key']!),
    ),
  ],
);

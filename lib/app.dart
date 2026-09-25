import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'core/navigation.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'data/store/active_playback.dart';
import 'ui/player/player_args.dart';

/// Root widget. Observes the app lifecycle so that resuming while a stream was
/// active jumps straight back into the player (Kotlin `MainActivity.onResume`).
/// Enables click-and-drag scrolling for mouse/trackpad (web + desktop) on top
/// of the usual touch drag.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class SrcTvApp extends StatefulWidget {
  const SrcTvApp({super.key});

  @override
  State<SrcTvApp> createState() => _SrcTvAppState();
}

class _SrcTvAppState extends State<SrcTvApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!ActivePlayback.isActive() || PlayerRuntime.isOpen) return;
    // Don't re-open a player the user just backed out of (a transient
    // inactive→resumed around the pop would otherwise stack a second player
    // that keeps playing audio underneath).
    if (DateTime.now().millisecondsSinceEpoch - PlayerRuntime.leftAt < 3000) {
      return;
    }
    final season = ActivePlayback.season();
    final episode = ActivePlayback.episode();
    final s = season >= 0 ? season : null;
    final e = episode >= 0 ? episode : null;
    final loc = watchLocation(
      type: ActivePlayback.type(),
      tmdbId: ActivePlayback.tmdbId(),
      season: s,
      episode: e,
    );
    final extra = PlayerArgs.stream(
      tmdbId: ActivePlayback.tmdbId(),
      type: ActivePlayback.type(),
      season: s,
      episode: e,
    );
    // Web navigates with `go` (URL reflects the video); native keeps `push`.
    if (kIsWeb) {
      appRouter.go(loc, extra: extra);
    } else {
      appRouter.push(loc, extra: extra);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SRC TV',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      // Allow click-and-drag to scroll rows with a mouse (web/desktop) — Flutter
      // otherwise only drag-scrolls with touch, so the horizontal rows (e.g.
      // Continue Watching, incl. its lazy-load-on-scroll) can't be dragged in a
      // browser. Harmless on Android (touch already works).
      scrollBehavior: const _AppScrollBehavior(),
      routerConfig: appRouter,
    );
  }
}

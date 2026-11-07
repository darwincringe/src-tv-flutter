import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/history_policy.dart';
import 'core/navigation.dart';
import 'core/router.dart';
import 'core/shell_return.dart';
import 'core/theme.dart';
import 'data/auth/auth_service.dart';
import 'data/store/active_playback.dart';
import 'data/sync/sync_service.dart';
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

/// The packaged TV build is still a web app, and Flutter's web defaults turn
/// arrow keys into page scrolling. A remote has no mouse, so those keys have
/// to move the focus ring instead, the same way they do on Android TV.
const _tizenWeb = bool.fromEnvironment('TIZEN_WEB');

final Map<ShortcutActivator, Intent>? _tizenShortcuts = _tizenWeb
    ? <ShortcutActivator, Intent>{
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            DirectionalFocusIntent(TraversalDirection.up),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            DirectionalFocusIntent(TraversalDirection.down),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            DirectionalFocusIntent(TraversalDirection.left),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            DirectionalFocusIntent(TraversalDirection.right),
      }
    : null;

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
    installAppHistoryGuard(
      listenable: appRouter.routeInformationProvider,
      currentUri: () => appRouter.routeInformationProvider.value.uri.toString(),
    );
    onDetailsBackMismatch = (path) {
      ShellReturn.hold = true;
      appRouter.go(path);
      ShellReturn.hold = false;
      ShellReturn.onShell(path);
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // The web player is an HTML video. Focusing it makes the browser report
    // "resumed" over and over, and each one was downloading the whole library.
    // Playback already saves progress on its own, so skip the account sync
    // until the player is closed.
    if (!PlayerRuntime.isOpen && AuthService.isSignedIn) {
      SyncService.sync();
      AuthService.refreshProfile();
    }
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
      shortcuts: _tizenShortcuts,
      routerConfig: appRouter,
    );
  }
}

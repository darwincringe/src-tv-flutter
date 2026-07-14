import 'package:flutter/material.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'data/store/active_playback.dart';
import 'ui/player/player_args.dart';

/// Root widget. Observes the app lifecycle so that resuming while a stream was
/// active jumps straight back into the player (Kotlin `MainActivity.onResume`).
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
    final season = ActivePlayback.season();
    final episode = ActivePlayback.episode();
    appRouter.push(
      '/player',
      extra: PlayerArgs.stream(
        tmdbId: ActivePlayback.tmdbId(),
        type: ActivePlayback.type(),
        season: season >= 0 ? season : null,
        episode: episode >= 0 ? episode : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SRC TV',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
    );
  }
}

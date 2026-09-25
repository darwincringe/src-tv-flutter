import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/url_strategy.dart'
    if (dart.library.html) 'core/url_strategy_web.dart';
import 'data/auth/auth_service.dart';
import 'data/store/active_playback.dart';
import 'data/store/library_store.dart';
import 'data/store/recommendation_seeds.dart';
import 'data/store/subtitle_pref.dart';
import 'data/store/watch_progress.dart';
import 'data/sync/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: clean path URLs (no /#/). No-op on native.
  configureUrlStrategy();
  // Artwork is now decoded at display size (see memCacheWidth on the image
  // widgets), so entries are ~5-15x smaller. Allow more of them so long rows
  // don't thrash the cache (evict + re-decode) while scrolling.
  PaintingBinding.instance.imageCache
    ..maximumSize = 400
    ..maximumSizeBytes = 100 << 20; // 100 MB
  await WatchProgressStore.init();
  await LibraryStore.init();
  await ActivePlayback.init();
  await RecommendationSeeds.init();
  await SubtitlePrefStore.init();
  await AuthService.init();
  // Wire the local stores to the account (no-op while signed out).
  SyncService.init();
  // If already signed in, pull the account's data in the background — the store
  // revision notifiers refresh the UI when it lands. Don't block startup on it.
  if (AuthService.isSignedIn) {
    SyncService.pullAll();
  }
  runApp(const ProviderScope(child: SrcTvApp()));
}

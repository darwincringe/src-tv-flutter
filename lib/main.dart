import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/store/active_playback.dart';
import 'data/store/recommendation_seeds.dart';
import 'data/store/subtitle_pref.dart';
import 'data/store/watch_progress.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Artwork is now decoded at display size (see memCacheWidth on the image
  // widgets), so entries are ~5-15x smaller. Allow more of them so long rows
  // don't thrash the cache (evict + re-decode) while scrolling.
  PaintingBinding.instance.imageCache
    ..maximumSize = 400
    ..maximumSizeBytes = 100 << 20; // 100 MB
  await WatchProgressStore.init();
  await ActivePlayback.init();
  await RecommendationSeeds.init();
  await SubtitlePrefStore.init();
  runApp(const ProviderScope(child: SrcTvApp()));
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/store/active_playback.dart';
import 'data/store/recommendation_seeds.dart';
import 'data/store/subtitle_pref.dart';
import 'data/store/watch_progress.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the image cache modest so browsing artwork doesn't add to memory
  // pressure alongside video playback on low-heap devices.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 60 << 20; // 60 MB
  await WatchProgressStore.init();
  await ActivePlayback.init();
  await RecommendationSeeds.init();
  await SubtitlePrefStore.init();
  runApp(const ProviderScope(child: SrcTvApp()));
}

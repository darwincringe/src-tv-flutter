import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'data/store/active_playback.dart';
import 'data/store/recommendation_seeds.dart';
import 'data/store/watch_progress.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await WatchProgressStore.init();
  await ActivePlayback.init();
  await RecommendationSeeds.init();
  runApp(const ProviderScope(child: SrcTvApp()));
}

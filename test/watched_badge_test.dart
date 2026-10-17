import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:srctv_flutter/data/store/watch_progress.dart';
import 'package:srctv_flutter/ui/widgets/watched_check.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WatchProgressStore.init();
  });

  testWidgets('a watched movie shows an orange box with a white check', (tester) async {
    WatchProgressStore.save(const WatchProgress(
      tmdbId: 4,
      type: 'movie',
      positionMs: 95,
      durationMs: 100,
    ));
    await tester.pumpWidget(const MaterialApp(
      home: MovieWatchedBadge(tmdbId: 4, size: 22),
    ));

    final icon = tester.widget<Icon>(find.byIcon(Icons.check));
    expect(icon.color, Colors.white);
    final box = tester.widget<Container>(
      find.ancestor(
        of: find.byIcon(Icons.check),
        matching: find.byType(Container),
      ).first,
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFFFF9800));

    WatchProgressStore.save(const WatchProgress(
      tmdbId: 4,
      type: 'movie',
      positionMs: 50,
      durationMs: 100,
    ));
    await tester.pump();
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('an episode under 95% has no check', (tester) async {
    WatchProgressStore.save(const WatchProgress(
      tmdbId: 9,
      type: 'tv',
      season: 1,
      episode: 2,
      positionMs: 40,
      durationMs: 100,
    ));
    await tester.pumpWidget(const MaterialApp(
      home: EpisodeWatchedBadge(tmdbId: 9, season: 1, episode: 2),
    ));
    expect(find.byIcon(Icons.check), findsNothing);
  });
}

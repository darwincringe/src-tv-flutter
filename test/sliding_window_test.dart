import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/ui/widgets/episode_window.dart';
import 'package:srctv_flutter/ui/widgets/sliding_window.dart';

void main() {
  test('a page of 10 moves by 5 and the last page stays full', () {
    expect(episodePageStart(start: 0, total: 23, forward: true), 5);
    expect(episodePageStart(start: 5, total: 23, forward: true), 10);
    expect(episodePageStart(start: 10, total: 23, forward: true), 13);
    expect(episodePageStart(start: 13, total: 23, forward: false), 8);
    expect(episodePageStart(start: 0, total: 8, forward: true), 0);
  });

  testWidgets('episodes slide forward and the back card returns', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: SlidingWindow(
            vertical: true,
            rows: 6,
            step: 5,
            itemCount: 12,
            imageUrl: (_) => null,
            itemBuilder: (_, i, _, _) => Text('ep-$i'),
          ),
        ),
      ),
    ));

    expect(find.text('ep-0'), findsOneWidget);
    expect(find.text('ep-4'), findsOneWidget);
    expect(find.text('ep-5'), findsNothing);
    expect(find.text('See more'), findsOneWidget);

    await tester.tap(find.text('See more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ep-0'), findsNothing);
    expect(find.text('ep-5'), findsOneWidget);
    expect(find.text('See more'), findsNWidgets(2));

    await tester.tap(find.text('See more').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ep-0'), findsOneWidget);
    expect(find.text('ep-5'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('more like this keeps a see more card at both ends', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 860,
          child: SlidingWindow(
            columns: 3,
            rows: 2,
            step: 5,
            itemCount: 14,
            imageUrl: (_) => null,
            itemBuilder: (_, i, _, _) => Text('like-$i'),
          ),
        ),
      ),
    ));

    expect(find.text('like-0'), findsOneWidget);
    expect(find.text('See more'), findsOneWidget);

    await tester.tap(find.text('See more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('like-0'), findsNothing);
    expect(find.text('like-5'), findsOneWidget);
    expect(find.text('See more'), findsNWidgets(2));
    await tester.pumpAndSettle();
  });

  testWidgets('episode see more keeps 10 rows and steps by 5', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EpisodeWindow(
          itemCount: 16,
          seeMoreBuilder: (_, _, _, onTap) => TextButton(
            onPressed: onTap,
            child: const Text('See more'),
          ),
          itemBuilder: (_, i, _, _) => Text('ep-$i'),
        ),
      ),
    ));

    expect(find.text('ep-0'), findsOneWidget);
    expect(find.text('ep-9'), findsOneWidget);
    expect(find.text('ep-10'), findsNothing);

    await tester.tap(find.text('See more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ep-0'), findsNothing);
    expect(find.text('ep-5'), findsOneWidget);
    expect(find.text('ep-14'), findsOneWidget);
    expect(find.text('ep-15'), findsNothing);
    await tester.pumpAndSettle();
  });
}

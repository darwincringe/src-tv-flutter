import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/ui/widgets/continue_watching_row.dart';

void main() {
  test('see more slides five titles and keeps a full window', () {
    // 3 columns x 3 rows. Twenty titles, so the last full window starts at 11.
    expect(
      posterWindowStart(
        start: 0,
        total: 20,
        window: 9,
        step: 5,
        forward: true,
      ),
      5,
    );
    expect(
      posterWindowStart(
        start: 5,
        total: 20,
        window: 9,
        step: 5,
        forward: false,
      ),
      0,
    );
    // Near the end the step shrinks so the grid stays full.
    expect(
      posterWindowStart(
        start: 10,
        total: 20,
        window: 9,
        step: 5,
        forward: true,
      ),
      11,
    );
    // Fewer titles than the window never pages.
    expect(
      posterWindowStart(
        start: 0,
        total: 4,
        window: 9,
        step: 5,
        forward: true,
      ),
      0,
    );
  });

  test('see more cards use the neighboring posters and a step of five', () {
    // One row of eight cells. The forward card takes one slot.
    final first = posterWindow(start: 0, total: 20, capacity: 8);
    expect(first.shown, 7);
    expect(first.canBack, isFalse);
    expect(first.canForward, isTrue);
    expect(first.nextIndex, 7);

    final next = nextPosterStart(
      start: 0,
      total: 20,
      capacity: 8,
      step: 5,
      forward: true,
    );
    final middle = posterWindow(start: next, total: 20, capacity: 8);
    expect(middle.start, 5);
    expect(middle.previousIndex, 4);
    expect(middle.canBack, isTrue);
    expect(middle.canForward, isTrue);

    final back = nextPosterStart(
      start: middle.start,
      total: 20,
      capacity: 8,
      step: 5,
      forward: false,
    );
    expect(back, 0);
  });

  testWidgets('see more hides the first five and the first card brings them back',
      (tester) async {
    // Two columns and three rows: six cells, one of them the See more card.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 200,
                  child: PagedPosterGrid(
                    itemCount: 20,
                    posterPath: (_) => null,
                    itemBuilder: (context, index, lead, focusNode) =>
                        Text('title-$index', key: ValueKey('title-$index')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('title-0'), findsOneWidget);
    expect(find.text('title-4'), findsOneWidget);
    expect(find.text('title-5'), findsNothing);
    expect(find.text('See more'), findsOneWidget);

    await tester.tap(find.text('See more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // Posters that are leaving are still in the tree while they slide out.
    expect(find.text('title-0'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('title-0'), findsNothing);
    expect(find.text('title-4'), findsNothing);
    expect(find.text('title-5'), findsOneWidget);
    expect(find.text('title-8'), findsOneWidget);
    expect(find.text('title-9'), findsNothing);
    expect(find.text('See more'), findsNWidgets(2));

    await tester.tap(find.text('See more').first);
    await tester.pumpAndSettle();

    expect(find.text('title-0'), findsOneWidget);
    expect(find.text('title-4'), findsOneWidget);
    expect(find.text('title-5'), findsNothing);
    expect(find.text('See more'), findsOneWidget);
  });

  testWidgets('portrait scrolls the row and keeps see more at the end',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: PagedPosterGrid(
              itemCount: 20,
              rows: 1,
              posterPath: _emptyPoster,
              itemBuilder: _title,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('title-0'), findsOneWidget);
    expect(tester.getTopLeft(find.text('title-0')).dx, lessThan(320));
    expect(tester.getTopLeft(find.text('See more')).dx, greaterThan(320));

    await tester.scrollUntilVisible(
      find.text('See more'),
      400,
      scrollable: find.byType(Scrollable),
    );
    final before = tester.getTopLeft(find.text('See more')).dx;
    expect(before, lessThan(320));
    final held = tester.getTopLeft(find.text('title-7')).dx;
    final offset = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position
        .pixels;

    await tester.tap(find.text('See more'));
    await tester.pumpAndSettle();

    expect(find.text('title-0'), findsOneWidget);
    expect(tester.getTopLeft(find.text('title-0')).dx, lessThan(0));
    expect(tester.getTopLeft(find.text('title-7')).dx, held);
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      offset,
    );
    expect(find.text('title-9'), findsOneWidget);
    var after = 0.0;
    final seeMore = find.text('See more');
    for (var i = 0; i < seeMore.evaluate().length; i++) {
      final dx = tester.getTopLeft(seeMore.at(i)).dx;
      if (dx > after) after = dx;
    }
    expect(after, greaterThan(before + 100));
  });

  testWidgets('a poster that stays slides into its new cell', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // One row of eight cells. Titles 5 and 6 are in both windows.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1100,
            child: PagedPosterGrid(
              itemCount: 20,
              rows: 1,
              posterPath: _emptyPoster,
              itemBuilder: _title,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = tester.getTopLeft(find.text('title-5'));
    await tester.tap(find.text('See more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    final during = tester.getTopLeft(find.text('title-5'));
    expect(during.dx, lessThan(before.dx));
    expect(during.dx, greaterThan(0));
    expect(find.text('title-0'), findsOneWidget);

    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.text('title-5'));
    expect(after.dx, lessThan(before.dx));
    expect(after.dx, greaterThan(0));
  });
}

String? _emptyPoster(int index) => null;

Widget _title(BuildContext context, int index, bool lead, FocusNode? focusNode) {
  return Text('title-$index', key: ValueKey('title-$index'));
}

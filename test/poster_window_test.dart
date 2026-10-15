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
    // The outgoing cards are still on screen while they slide away.
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
}

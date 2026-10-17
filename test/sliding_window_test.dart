import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/ui/widgets/sliding_window.dart';

void main() {
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
}

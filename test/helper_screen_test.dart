import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/data/models/media_item.dart';
import 'package:srctv_flutter/ui/helper/helper_screen.dart';

void main() {
  setUp(() {
    HelperMemory.query = '';
    HelperMemory.results = const [];
    HelperMemory.note = '';
    HelperMemory.hasMore = false;
  });

  testWidgets('the remote starts on the first idea and Down moves on',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: HelperScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Disturbing movies'), findsOneWidget);
    expect(find.text('Find'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'helper-idea-0',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'helper-idea-1',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'helper-idea-0',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'helper-find',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'helper-field',
    );

    await tester.pumpAndSettle();
  });

  testWidgets('a rebuilt helper keeps the query and the results', (tester) async {
    HelperMemory.save(
      query: 'Sad movies',
      note: 'Movies · sad',
      results: const [
        MediaItem(id: 1, title: 'The Whale', mediaType: 'movie'),
      ],
      hasMore: false,
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: HelperScreen())),
      ),
    );
    await tester.pump();

    expect(find.text('Sad movies'), findsWidgets);
    expect(find.text('The Whale'), findsOneWidget);
    expect(find.text('Results'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}

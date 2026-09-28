import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:srctv_flutter/core/history_policy.dart';

void main() {
  test('back skips another episode of the same title', () {
    final left = Uri.parse('/watch/tv/7?s=1&e=2');
    final landed = Uri.parse('/watch/tv/7?s=1&e=1');
    expect(shouldSkipHistoryEntry(left, landed), isTrue);
  });

  test('back skips a duplicate of the same page', () {
    final page = Uri.parse('/details/tv/7');
    expect(shouldSkipHistoryEntry(page, page), isTrue);
  });

  test('back stops on details and on a different title', () {
    final player = Uri.parse('/watch/tv/7?s=1&e=2');
    expect(
      shouldSkipHistoryEntry(player, Uri.parse('/details/tv/7')),
      isFalse,
    );
    expect(
      shouldSkipHistoryEntry(player, Uri.parse('/watch/tv/8?s=1&e=1')),
      isFalse,
    );
    expect(
      shouldSkipHistoryEntry(
        Uri.parse('/details/tv/7'),
        Uri.parse('/search'),
      ),
      isFalse,
    );
  });

  testWidgets('changing episode replaces the history entry', (tester) async {
    final updates = <Map<dynamic, dynamic>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.navigation,
      (call) async {
        if (call.method == 'routeInformationUpdated') {
          updates.add(Map<dynamic, dynamic>.from(call.arguments as Map));
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        null,
      );
    });

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
        GoRoute(
          path: '/details/:type/:id',
          builder: (_, _) => const SizedBox(),
        ),
        GoRoute(
          path: '/watch/:type/:id',
          builder: (_, _) => const SizedBox(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.go('/details/tv/7');
    await tester.pumpAndSettle();
    router.go('/watch/tv/7?s=1&e=1');
    await tester.pumpAndSettle();
    updates.clear();

    final context = router.routerDelegate.navigatorKey.currentContext!;
    Router.neglect(context, () {
      context.replace('/watch/tv/7?s=1&e=2');
    });
    await tester.pumpAndSettle();

    expect(updates, isNotEmpty);
    final episode = updates.lastWhere(
      (u) => u['uri'].toString().contains('e=2'),
    );
    expect(episode['replace'], isTrue);
    expect(router.routeInformationProvider.value.uri.toString(), contains('e=2'));
  });
}

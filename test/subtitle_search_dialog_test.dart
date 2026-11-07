import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/data/subtitle/opensubtitles_client.dart';
import 'package:srctv_flutter/ui/player/subtitle_search_dialog.dart';

void main() {
  late _FakeSubtitles client;

  setUp(() {
    clearSubtitleSearchMemory();
    client = _FakeSubtitles();
  });

  testWidgets('closing or picking a subtitle keeps the result list', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSubtitleSearchDialog(
              context,
              initialQuery: 'Dune',
              title: 'Dune',
              tmdbId: 1,
              type: 'movie',
              client: client,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    Future<void> open() async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await open();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.text('WEBRip'), findsOneWidget);
    expect(client.searches, 1);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await open();
    expect(find.text('WEBRip'), findsOneWidget);
    expect(client.searches, 1);

    await tester.tap(find.text('WEBRip'));
    await tester.pumpAndSettle();

    await open();
    expect(find.text('WEBRip'), findsOneWidget);
    expect(client.searches, 1);
  });
}

class _FakeSubtitles extends OpenSubtitlesClient {
  int searches = 0;

  @override
  Future<List<OpenSubtitleHit>> search({
    required String query,
    int? season,
    int? episode,
    int? tmdbId,
    String? type,
    String lang = 'en',
  }) async {
    searches++;
    return const [
      OpenSubtitleHit(fileId: '9', label: 'WEBRip', detail: 'English'),
    ];
  }

  @override
  Future<String> downloadSrt(String fileId) async =>
      '1\n00:00:00,000 --> 00:00:01,000\nHi\n';
}

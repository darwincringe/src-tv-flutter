import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/data/stream/extract_response.dart';
import 'package:srctv_flutter/data/stream/mirror_choice.dart';
import 'package:srctv_flutter/ui/player/mirror_bar.dart';

void main() {
  const catflix = StreamMirror(
    hlsUrl: 'https://cdn/catflix.m3u8',
    source: 'catflix',
    quality: '1080p',
  );
  const superstream = StreamMirror(
    hlsUrl: 'https://cdn/super.m3u8',
    source: 'superstream',
    quality: '1080p',
  );
  const vaplayer = StreamMirror(
    hlsUrl: 'https://cdn/vaplayer.m3u8',
    source: 'vaplayer',
    quality: '720p',
  );

  ExtractResponse sample({String? hlsUrl}) => ExtractResponse(
        success: true,
        hlsUrl: hlsUrl ?? catflix.hlsUrl,
        mirrors: const [catflix, superstream, vaplayer],
      );

  test('saved source is used when that mirror exists', () {
    final pick = pickPlayback(sample(), 'catflix');
    expect(pick!.url, catflix.hlsUrl);
    expect(pick.index, 0);
  });

  test('a missing saved source falls back to vaplayer', () {
    final res = ExtractResponse(
      success: true,
      hlsUrl: catflix.hlsUrl,
      mirrors: const [catflix, vaplayer],
    );
    final pick = pickPlayback(res, 'superstream');
    expect(pick!.url, vaplayer.hlsUrl);
    expect(pick.index, 1);
    expect(needsVaplayerRetry(res, 'superstream', pick), isFalse);
  });

  test('asks for vaplayer again when the list does not include it', () {
    final res = ExtractResponse(
      success: true,
      hlsUrl: catflix.hlsUrl,
      mirrors: const [catflix],
    );
    final pick = pickPlayback(res, 'superstream');
    expect(pick!.url, catflix.hlsUrl);
    expect(needsVaplayerRetry(res, 'superstream', pick), isTrue);
  });

  test('no saved source plays the response url', () {
    final pick = pickPlayback(sample(hlsUrl: superstream.hlsUrl), null);
    expect(pick!.url, superstream.hlsUrl);
    expect(pick.index, 1);
  });

  test('button labels never include the provider name', () {
    expect(mirrorButtonLabel(0, catflix), 'Source 1 1080p');
    expect(mirrorButtonLabel(1, superstream), 'Source 2 1080p');
    expect(mirrorButtonLabel(2, vaplayer), 'Source 3 720p');
    final joined = [
      mirrorButtonLabel(0, catflix),
      mirrorButtonLabel(1, superstream),
      mirrorButtonLabel(2, vaplayer),
    ].join(' ').toLowerCase();
    expect(joined.contains('catflix'), isFalse);
    expect(joined.contains('superstream'), isFalse);
    expect(joined.contains('vaplayer'), isFalse);
  });

  test('a filtered source response still keeps the full mirror list', () async {
    final calls = <String?>[];
    final resolved = await resolvePlayback(
      preferred: 'catflix',
      extract: (source) async {
        calls.add(source);
        if (source == 'catflix') {
          return const ExtractResponse(
            success: true,
            hlsUrl: 'https://cdn/catflix.m3u8',
            mirrors: [catflix],
          );
        }
        return sample();
      },
    );
    expect(calls, ['catflix', null]);
    expect(resolved!.url, catflix.hlsUrl);
    expect(resolved.index, 0);
    expect(resolved.response.mirrors, [catflix, superstream, vaplayer]);
  });

  testWidgets('select key activates the focused mirror', (tester) async {
    final nodes = [FocusNode(), FocusNode()];
    addTearDown(() {
      for (final n in nodes) {
        n.dispose();
      }
    });
    var tapped = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MirrorBar(
            mirrors: const [catflix, vaplayer],
            selected: 0,
            focusNodes: nodes,
            onSelect: (i) => tapped = i,
          ),
        ),
      ),
    );

    expect(find.text('Source 1 1080p'), findsOneWidget);
    expect(find.text('Source 2 720p'), findsOneWidget);
    expect(find.textContaining('catflix'), findsNothing);
    expect(find.textContaining('vaplayer'), findsNothing);

    nodes[1].requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(tapped, 1);
  });
}

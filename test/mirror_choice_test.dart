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

  test('nothing saved starts at vaplayer and still asks for the others', () {
    expect(playbackSourceQueue(null).first, 'vaplayer');
    expect(playbackSourceQueue(''), playbackSources);
    expect(playbackSourceQueue(null), isNot(contains('nashville')));
  });

  test('a saved source is requested first', () {
    final queue = playbackSourceQueue('Catflix');
    expect(queue.first, 'catflix');
    expect(queue, contains('vaplayer'));
    expect(queue.where((source) => source == 'catflix'), hasLength(1));
  });

  test('a pinned response keeps that provider, and vaplayer keeps nashville', () {
    final mixed = ExtractResponse(
      success: true,
      hlsUrl: catflix.hlsUrl,
      source: 'catflix',
      mirrors: const [catflix, vaplayer],
    );
    expect(mirrorsForPinned(mixed, 'catflix'), [catflix]);
    final fallback = ExtractResponse(
      success: true,
      hlsUrl: 'https://cdn/nashville.m3u8',
      source: 'nashville',
      quality: '1080p',
      mirrors: const [
        StreamMirror(
          hlsUrl: 'https://cdn/nashville.m3u8',
          source: 'nashville',
          quality: '1080p',
        ),
        catflix,
      ],
    );
    final kept = mirrorsForPinned(fallback, 'vaplayer');
    expect(kept.map((mirror) => mirror.source), ['nashville']);
  });

  test('button labels show the provider and quality', () {
    expect(mirrorButtonLabel(0, catflix), 'Catflix 1080p');
    expect(mirrorButtonLabel(1, superstream), 'Superstream 1080p');
    expect(mirrorButtonLabel(2, vaplayer), 'Vaplayer 720p');
  });

  test('sources load one at a time and playback starts on the saved one', () async {
    final calls = <String>[];
    final slices = await playbackSlices(
      preferred: 'flixhq',
      extract: (source) async {
        calls.add(source);
        if (source == 'flixhq') {
          return const ExtractResponse(
            success: true,
            hlsUrl: 'https://cdn/flix.m3u8',
            source: 'flixhq',
            subtitles: ['https://subs/flix.srt&release=flixhq.en'],
            mirrors: [
              StreamMirror(
                hlsUrl: 'https://cdn/flix.m3u8',
                source: 'flixhq',
                quality: '1080p',
              ),
            ],
          );
        }
        if (source == 'vaplayer') {
          return const ExtractResponse(
            success: true,
            hlsUrl: 'https://cdn/vaplayer.m3u8',
            source: 'vaplayer',
            subtitles: ['https://subs/va.srt&release=vaplayer.en'],
            mirrors: [vaplayer],
          );
        }
        return const ExtractResponse(success: false);
      },
    ).toList();
    expect(calls.first, 'flixhq');
    expect(calls[1], 'vaplayer');
    expect(calls, isNot(contains(null)));
    expect(slices.first.playUrl, 'https://cdn/flix.m3u8');
    expect(slices.first.playIndex, 0);
    expect(slices.first.subtitles, ['https://subs/flix.srt&release=flixhq.en']);
    final last = slices.last;
    expect(last.playUrl, isNull);
    expect(last.mirrors.map((mirror) => mirror.source), ['flixhq', 'vaplayer']);
    expect(last.subtitles, [
      'https://subs/flix.srt&release=flixhq.en',
      'https://subs/va.srt&release=vaplayer.en',
    ]);
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

    expect(find.text('Catflix 1080p'), findsOneWidget);
    expect(find.text('Vaplayer 720p'), findsOneWidget);

    nodes[1].requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(tapped, 1);
  });
}

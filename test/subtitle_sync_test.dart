import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/ui/player/subtitle_parser.dart';
import 'package:srctv_flutter/ui/player/subtitle_sync.dart';

void main() {
  Map<int, double> track(int from, int to, List<(int, int)> speech) {
    final energy = <int, double>{};
    for (var bin = from; bin <= to; bin++) {
      final talking = speech.any((r) => bin >= r.$1 && bin <= r.$2);
      energy[bin] = talking ? 1.0 : 0.05;
    }
    return energy;
  }

  List<SubtitleCue> cues(List<(int, int)> ranges) => [
        for (final r in ranges)
          SubtitleCue(
            start: Duration(milliseconds: r.$1 * 100),
            end: Duration(milliseconds: r.$2 * 100),
            text: 'line',
          ),
      ];

  const lines = <(int, int)>[(20, 40), (70, 95), (130, 155), (190, 215)];

  test('leaves an already lined-up track alone', () {
    expect(subtitleSyncOffsetMs(track(0, 250, lines), cues(lines)), 0);
  });

  test('shifts late captions earlier by the delay', () {
    final late = [for (final r in lines) (r.$1 + 20, r.$2 + 20)];
    expect(subtitleSyncOffsetMs(track(0, 280, lines), cues(late)), 2000);
  });

  test('shifts early captions later by the lead', () {
    final early = [for (final r in lines) (r.$1 - 15, r.$2 - 15)];
    expect(subtitleSyncOffsetMs(track(0, 250, lines), cues(early)), -1500);
  });

  test('does not guess when the whole stretch is loud', () {
    final loud = {for (var i = 0; i < 200; i++) i: 1.0};
    expect(subtitleSyncOffsetMs(loud, cues(lines)), isNull);
  });

  test('does not guess when speech never matches the cues', () {
    final speech = track(0, 250, [(5, 12), (40, 48), (100, 108), (160, 168)]);
    final unrelated = cues([(220, 235), (260, 275), (300, 315), (340, 355)]);
    expect(subtitleSyncOffsetMs(speech, unrelated), isNull);
  });

  SubtitleCue line(int startMs, String text) => SubtitleCue(
        start: Duration(milliseconds: startMs),
        end: Duration(milliseconds: startMs + 2500),
        text: text,
      );

  test('moves late captions back to the spoken line', () {
    final heardAt = 10000;
    final file = [
      line(8000, 'Nothing useful here at all.'),
      line(15000, 'The ship is leaving the harbor tonight.'),
    ];
    expect(
      subtitleLineOffsetMs(
        transcript: 'the ship is leaving the harbor tonight',
        videoMs: heardAt,
        cues: file,
      ),
      5000,
    );
  });

  test('moves early captions forward to the spoken line', () {
    final file = [
      line(10000, '<i>Hello there, how are you doing today?</i>'),
    ];
    expect(
      subtitleLineOffsetMs(
        transcript: 'hello there how are you doing today',
        videoMs: 12500,
        cues: file,
      ),
      -2500,
    );
  });

  test('still matches a slightly misheard line', () {
    final file = [
      line(40000, 'Get out of the building before sunrise.'),
    ];
    expect(
      subtitleLineOffsetMs(
        transcript: 'get out of the building before sunset',
        videoMs: 38000,
        cues: file,
      ),
      2000,
    );
  });

  test('ignores a line that is not in the subtitles', () {
    final file = [
      line(10000, 'The ship is leaving the harbor tonight.'),
    ];
    expect(
      subtitleLineOffsetMs(
        transcript: 'completely different words about the weather',
        videoMs: 10000,
        cues: file,
      ),
      isNull,
    );
  });

  test('ignores a repeated line from another scene', () {
    final file = [
      line(10000, 'The ship is leaving the harbor tonight.'),
      line(400000, 'The ship is leaving the harbor tonight.'),
    ];
    expect(
      subtitleLineOffsetMs(
        transcript: 'the ship is leaving the harbor tonight',
        videoMs: 10000,
        cues: file,
      ),
      0,
    );
  });
}

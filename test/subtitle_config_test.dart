import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/ui/player/subtitle_config.dart';

void main() {
  group('detectLanguage', () {
    test('matches keywords in a filename', () {
      expect(detectLanguage('The.Movie.2021.english.srt'), 'en');
      expect(detectLanguage('some.tagalog.file.srt'), 'tl');
      expect(detectLanguage('nolang.srt'), isNull);
    });
  });

  group('apiSubtitleOption', () {
    test('label uses the release= param', () {
      final o = apiSubtitleOption(
        'http://host:4000/movie-subtitle-srt?url=x/english.srt&release=WEBRIP',
      );
      expect(o.label, 'WEBRIP');
      expect(o.language, 'en');
    });

    test('falls back to language display name, then Subtitle', () {
      final withLang = apiSubtitleOption('http://host/s?url=a.spanish.srt');
      expect(withLang.label, 'Spanish');

      final none = apiSubtitleOption('http://host/s?url=a.srt');
      expect(none.label, 'Subtitle');
    });
  });

  test('uploadedSubtitleOption labels', () {
    expect(uploadedSubtitleOption('/a.srt', 0).label, 'Uploaded');
    expect(uploadedSubtitleOption('/b.srt', 1).label, 'Uploaded 2');
  });
}

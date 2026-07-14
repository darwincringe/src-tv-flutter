import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/data/models/language.dart';
import 'package:srctv_flutter/data/models/media_item.dart';
import 'package:srctv_flutter/data/models/videos.dart';

void main() {
  group('MediaItem', () {
    test('displayTitle prefers title then name', () {
      expect(
        const MediaItem(id: 1, title: 'Movie', name: 'Show').displayTitle,
        'Movie',
      );
      expect(const MediaItem(id: 1, name: 'Show').displayTitle, 'Show');
      expect(const MediaItem(id: 1).displayTitle, '');
    });

    test('year is first 4 chars of the relevant date', () {
      expect(const MediaItem(id: 1, releaseDate: '2021-05-01').year, '2021');
      expect(const MediaItem(id: 1, firstAirDate: '2019-01-01').year, '2019');
      expect(const MediaItem(id: 1, releaseDate: '20').year, isNull);
      expect(const MediaItem(id: 1).year, isNull);
    });

    test('resolvedType returns real type or fallback', () {
      expect(const MediaItem(id: 1, mediaType: 'tv').resolvedType('movie'), 'tv');
      expect(
        const MediaItem(id: 1, mediaType: 'person').resolvedType('movie'),
        'movie',
      );
      expect(const MediaItem(id: 1).resolvedType('tv'), 'tv');
    });

    test('copyWith tags mediaType', () {
      final tagged = const MediaItem(id: 1).copyWith(mediaType: 'movie');
      expect(tagged.mediaType, 'movie');
      expect(tagged.id, 1);
    });
  });

  group('VideosDto.bestTrailerKey', () {
    test('prefers official YouTube Trailer', () {
      const v = VideosDto(results: [
        VideoDto(key: 'teaser', site: 'YouTube', type: 'Teaser'),
        VideoDto(key: 'unofficial', site: 'YouTube', type: 'Trailer'),
        VideoDto(key: 'official', site: 'YouTube', type: 'Trailer', official: true),
      ]);
      expect(v.bestTrailerKey(), 'official');
    });

    test('falls back to teaser, ignores non-YouTube', () {
      const v = VideosDto(results: [
        VideoDto(key: 'vimeo', site: 'Vimeo', type: 'Trailer', official: true),
        VideoDto(key: 'teaser', site: 'YouTube', type: 'Teaser'),
      ]);
      expect(v.bestTrailerKey(), 'teaser');
    });

    test('returns null when no YouTube videos', () {
      const v = VideosDto(results: [
        VideoDto(key: 'x', site: 'Vimeo', type: 'Trailer'),
      ]);
      expect(v.bestTrailerKey(), isNull);
    });
  });

  group('languageName', () {
    test('maps known codes and handles unknown/null', () {
      expect(languageName('en'), 'English');
      expect(languageName('tl'), 'Tagalog');
      expect(languageName('xx'), 'XX');
      expect(languageName(null), 'Unknown');
      expect(languageName(''), 'Unknown');
    });
  });
}

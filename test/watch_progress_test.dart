import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/data/store/watch_progress.dart';

void main() {
  group('WatchProgress', () {
    test('isResumable requires being past 5s and not near the end', () {
      expect(
        const WatchProgress(
          tmdbId: 1,
          type: 'movie',
          positionMs: 60000,
          durationMs: 600000,
        ).isResumable,
        isTrue,
      );
      expect(
        const WatchProgress(
          tmdbId: 1,
          type: 'movie',
          positionMs: 3000,
          durationMs: 600000,
        ).isResumable,
        isFalse,
      );
      expect(
        const WatchProgress(
          tmdbId: 1,
          type: 'movie',
          positionMs: 595000,
          durationMs: 600000,
        ).isResumable,
        isFalse,
      );
    });

    test('isContinuable for a TV record queued at position 0', () {
      expect(
        const WatchProgress(tmdbId: 1, type: 'tv', positionMs: 0).isContinuable,
        isTrue,
      );
      expect(
        const WatchProgress(tmdbId: 1, type: 'movie', positionMs: 0)
            .isContinuable,
        isFalse,
      );
      expect(
        const WatchProgress(
          tmdbId: 1,
          type: 'tv',
          positionMs: 0,
          completed: true,
        ).isContinuable,
        isFalse,
      );
    });

    test('watchedFraction is clamped 0..1', () {
      expect(
        const WatchProgress(
          tmdbId: 1,
          type: 'movie',
          positionMs: 300000,
          durationMs: 600000,
        ).watchedFraction,
        0.5,
      );
      expect(
        const WatchProgress(tmdbId: 1, type: 'movie').watchedFraction,
        0.0,
      );
    });

    test('toJson/fromJson round-trips', () {
      const p = WatchProgress(
        tmdbId: 42,
        type: 'tv',
        season: 2,
        episode: 5,
        positionMs: 1234,
        durationMs: 5678,
        updatedAt: 999,
        title: 'Show',
        posterPath: '/p.jpg',
        completed: false,
      );
      final round = WatchProgress.fromJson(p.toJson());
      expect(round.tmdbId, 42);
      expect(round.season, 2);
      expect(round.episode, 5);
      expect(round.title, 'Show');
      expect(round.positionMs, 1234);
    });
  });
}

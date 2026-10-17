import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

    test('95% marks a movie watched and a rewatch at 50% keeps it', () {
      final atLine = retainWatched(const WatchProgress(
        tmdbId: 1,
        type: 'movie',
        positionMs: 95,
        durationMs: 100,
      ));
      expect(atLine.isMovieWatched, isTrue);

      final short = retainWatched(const WatchProgress(
        tmdbId: 1,
        type: 'movie',
        positionMs: 94,
        durationMs: 100,
      ));
      expect(short.isMovieWatched, isFalse);

      final rewatch = retainWatched(
        const WatchProgress(
          tmdbId: 1,
          type: 'movie',
          positionMs: 50,
          durationMs: 100,
        ),
        previous: atLine,
      );
      expect(rewatch.positionMs, 50);
      expect(rewatch.completed, isFalse);
      expect(rewatch.isMovieWatched, isTrue);
    });

    test('an episode stays watched when the series moves on or is rewatched', () {
      final first = retainWatched(const WatchProgress(
        tmdbId: 3,
        type: 'tv',
        season: 1,
        episode: 3,
        positionMs: 950,
        durationMs: 1000,
      ));
      expect(first.isEpisodeWatched(1, 3), isTrue);
      expect(first.isEpisodeWatched(1, 4), isFalse);

      final rewatch = retainWatched(
        const WatchProgress(
          tmdbId: 3,
          type: 'tv',
          season: 1,
          episode: 3,
          positionMs: 500,
          durationMs: 1000,
        ),
        previous: first,
      );
      expect(rewatch.isEpisodeWatched(1, 3), isTrue);

      final advanced = retainWatched(
        const WatchProgress(
          tmdbId: 3,
          type: 'tv',
          season: 1,
          episode: 4,
          positionMs: 0,
        ),
        previous: rewatch,
        finishedSeason: 1,
        finishedEpisode: 3,
      );
      expect(advanced.episode, 4);
      expect(advanced.isEpisodeWatched(1, 3), isTrue);
      expect(advanced.isEpisodeWatched(1, 4), isFalse);
    });
  });

  test('the store keeps a watched mark through a later save', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await WatchProgressStore.init();

    WatchProgressStore.save(const WatchProgress(
      tmdbId: 7,
      type: 'movie',
      positionMs: 95000,
      durationMs: 100000,
    ));
    WatchProgressStore.save(const WatchProgress(
      tmdbId: 7,
      type: 'movie',
      positionMs: 50000,
      durationMs: 100000,
    ));
    final movie = WatchProgressStore.get('movie', 7)!;
    expect(movie.positionMs, 50000);
    expect(movie.isMovieWatched, isTrue);

    WatchProgressStore.save(const WatchProgress(
      tmdbId: 8,
      type: 'tv',
      season: 2,
      episode: 1,
      positionMs: 1000,
      durationMs: 1000,
    ));
    WatchProgressStore.save(
      const WatchProgress(
        tmdbId: 8,
        type: 'tv',
        season: 2,
        episode: 2,
        positionMs: 0,
      ),
      finishedSeason: 2,
      finishedEpisode: 1,
    );
    WatchProgressStore.save(const WatchProgress(
      tmdbId: 8,
      type: 'tv',
      season: 2,
      episode: 1,
      positionMs: 400,
      durationMs: 1000,
    ));
    final show = WatchProgressStore.get('tv', 8)!;
    expect(show.positionMs, 400);
    expect(show.isEpisodeWatched(2, 1), isTrue);
    expect(show.isEpisodeWatched(2, 2), isFalse);
  });
}

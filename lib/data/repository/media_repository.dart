import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../introdb/introdb_client.dart';
import '../models/details_dto.dart';
import '../models/language.dart';
import '../models/media_details.dart';
import '../models/media_item.dart';
import '../store/recommendation_seeds.dart';
import '../store/watch_progress.dart';
import '../stream/extract_response.dart';
import '../stream/stream_client.dart';
import '../tmdb/tmdb_api.dart';

/// Single source of truth for catalog data, mirroring the Kotlin
/// `MediaRepository`: builds the Home/Movies/Series rows, resolves details and
/// episodes, provides search, similar/recommended, and continue-watching.
/// Results are cached in memory for the app's lifetime.
class MediaRepository {
  MediaRepository({TmdbApi? api, StreamClient? stream, IntroDbClient? introDb})
      : _api = api ?? TmdbApi(),
        _stream = stream ?? StreamClient(),
        _introDb = introDb ?? IntroDbClient();

  final TmdbApi _api;
  final StreamClient _stream;
  final IntroDbClient _introDb;

  static const int rowLimit = 10;
  static const String netflix = '8';
  static const String region = 'PH';

  // Caches
  final Map<String, List<CategoryRow>> _pageCache = {};
  final Map<String, MediaDetails> _detailsCache = {};
  final Map<String, List<Episode>> _episodeCache = {};
  final Map<String, List<MediaItem>> _similarCache = {};
  final Map<String, List<MediaItem>> _searchCache = {};

  // ---- Row helpers -------------------------------------------------------

  List<MediaItem> _forRow(List<MediaItem> items) => items
      .where((i) => i.posterPath != null && i.posterPath!.isNotEmpty)
      .take(rowLimit)
      .toList();

  List<MediaItem> _tag(List<MediaItem> items, String type) =>
      items.map((i) => i.copyWith(mediaType: type)).toList();

  List<MediaItem> _interleave(List<MediaItem> a, List<MediaItem> b) {
    final out = <MediaItem>[];
    final n = math.max(a.length, b.length);
    for (var i = 0; i < n; i++) {
      if (i < a.length) out.add(a[i]);
      if (i < b.length) out.add(b[i]);
    }
    return out;
  }

  List<MediaItem> _withPosters(List<MediaItem> items) => items
      .where((i) => i.posterPath != null && i.posterPath!.isNotEmpty)
      .toList();

  bool _isMovieOrTv(MediaItem i) {
    final t = i.mediaType;
    return t == 'movie' || t == 'tv';
  }

  // ---- Pages -------------------------------------------------------------

  Future<List<CategoryRow>> homeRows() =>
      _cachedPage('home', () async {
        final results = await Future.wait([
          _api.trendingAllWeek(),
          _api.popularTv(),
          _api.discoverMoviesByProvider(netflix, region),
          _api.discoverTvByProvider(netflix, region),
          _api.discoverMovies('99'), // Documentaries
        ]);
        final trending = _forRow(results[0]);
        final popularSeries = _forRow(results[1]);
        final netflixMovies = _tag(_withPosters(results[2]), 'movie');
        final netflixTv = _tag(_withPosters(results[3]), 'tv');
        final netflixRow =
            _interleave(netflixMovies, netflixTv).take(rowLimit).toList();
        final docs = _forRow(results[4]);

        return _nonEmpty([
          CategoryRow(title: 'Trending Now', fallbackType: 'movie', items: trending),
          CategoryRow(title: 'Popular Series', fallbackType: 'tv', items: popularSeries),
          CategoryRow(
            title: 'Popular on Netflix Philippines',
            fallbackType: 'movie',
            items: netflixRow,
          ),
          CategoryRow(title: 'Documentaries', fallbackType: 'movie', items: docs),
        ]);
      });

  Future<List<CategoryRow>> movieRows() =>
      _cachedPage('movies', () async {
        final results = await Future.wait([
          _api.nowPlayingMovies(),
          _api.popularMovies(),
          _api.topRatedMovies(),
          _api.discoverMovies('28'), // Action
          _api.discoverMovies('35'), // Comedy
          _api.discoverMovies('27'), // Horror
          _api.discoverMovies('16'), // Animation
        ]);
        return _nonEmpty([
          CategoryRow(title: 'Now Playing', fallbackType: 'movie', items: _forRow(results[0])),
          CategoryRow(title: 'Popular', fallbackType: 'movie', items: _forRow(results[1])),
          CategoryRow(title: 'Top Rated', fallbackType: 'movie', items: _forRow(results[2])),
          CategoryRow(title: 'Action', fallbackType: 'movie', items: _forRow(results[3])),
          CategoryRow(title: 'Comedy', fallbackType: 'movie', items: _forRow(results[4])),
          CategoryRow(title: 'Horror', fallbackType: 'movie', items: _forRow(results[5])),
          CategoryRow(title: 'Animation', fallbackType: 'movie', items: _forRow(results[6])),
        ]);
      });

  Future<List<CategoryRow>> seriesRows() =>
      _cachedPage('series', () async {
        final results = await Future.wait([
          _api.popularTv(),
          _api.topRatedTv(),
          _api.discoverTv('35'), // Comedy
          _api.discoverTv('10765'), // Sci-Fi & Fantasy
          _api.discoverTv('16'), // Animation
          _api.discoverTv('99'), // Documentary
        ]);
        return _nonEmpty([
          CategoryRow(title: 'Popular', fallbackType: 'tv', items: _forRow(results[0])),
          CategoryRow(title: 'Top Rated', fallbackType: 'tv', items: _forRow(results[1])),
          CategoryRow(title: 'Comedy', fallbackType: 'tv', items: _forRow(results[2])),
          CategoryRow(title: 'Sci-Fi & Fantasy', fallbackType: 'tv', items: _forRow(results[3])),
          CategoryRow(title: 'Animation', fallbackType: 'tv', items: _forRow(results[4])),
          CategoryRow(title: 'Documentary', fallbackType: 'tv', items: _forRow(results[5])),
        ]);
      });

  List<CategoryRow> _nonEmpty(List<CategoryRow> rows) =>
      rows.where((r) => r.items.isNotEmpty).toList();

  Future<List<CategoryRow>> _cachedPage(
    String key,
    Future<List<CategoryRow>> Function() build,
  ) async {
    final cached = _pageCache[key];
    if (cached != null) return cached;
    final rows = await build();
    _pageCache[key] = rows;
    return rows;
  }

  // ---- Similar / search --------------------------------------------------

  Future<List<MediaItem>> similar(String type, int id) async {
    final key = '$type-$id';
    final cached = _similarCache[key];
    if (cached != null) return cached;
    final recs = type == 'tv'
        ? await _api.tvRecommendations(id)
        : await _api.movieRecommendations(id);
    final filtered = recs
        .where((i) => i.backdropPath != null && i.backdropPath!.isNotEmpty)
        .toList();
    _similarCache[key] = filtered;
    return filtered;
  }

  Future<List<MediaItem>> search(String query) async {
    final key = query.toLowerCase().trim();
    if (key.isEmpty) return [];
    final cached = _searchCache[key];
    if (cached != null) return cached;
    final results = await _api.searchMulti(query);
    final filtered =
        _withPosters(results.where(_isMovieOrTv).toList());
    _searchCache[key] = filtered;
    return filtered;
  }

  // ---- Details / episodes ------------------------------------------------

  Future<MediaDetails> details(String type, int id) async {
    final key = '$type-$id';
    final cached = _detailsCache[key];
    if (cached != null) return cached;
    final MediaDetails d;
    if (type == 'tv') {
      final dto = await _api.tvDetails(id);
      d = _tvToDetails(dto, comingSoon: isComingSoon(dto.firstAirDate));
    } else {
      final dto = await _api.movieDetails(id);
      // "Coming Soon" for movies = TMDB lists no watch provider in our region.
      var comingSoon = false;
      try {
        comingSoon = !(await _api.movieHasProviders(id, region));
      } catch (_) {
        comingSoon = false; // never falsely tag on a failed lookup
      }
      d = _movieToDetails(dto, comingSoon: comingSoon);
    }
    _detailsCache[key] = d;
    return d;
  }

  Future<List<Episode>> episodes(int id, int season) async {
    final key = '$id-$season';
    final cached = _episodeCache[key];
    if (cached != null) return cached;
    final eps = (await _api.seasonDetails(id, season)).episodes;
    _episodeCache[key] = eps;
    return eps;
  }

  MediaDetails _movieToDetails(MovieDetailsDto dto, {bool comingSoon = false}) =>
      MediaDetails(
        id: dto.id,
        isTv: false,
        comingSoon: comingSoon,
        title: dto.title ?? '',
        tagline: (dto.tagline?.isNotEmpty ?? false) ? dto.tagline : null,
        overview: dto.overview ?? '',
        backdropPath: dto.backdropPath,
        posterPath: dto.posterPath,
        year: _year(dto.releaseDate),
        rating: dto.voteAverage ?? 0,
        runtimeMinutes: dto.runtime,
        language: languageName(dto.originalLanguage),
        genres: dto.genres
            .map((g) => g.name ?? '')
            .where((s) => s.isNotEmpty)
            .toList(),
        cast: (dto.credits?.cast ?? const []).take(12).toList(),
        trailerKey: dto.videos?.bestTrailerKey(),
        releaseDate: dto.releaseDate,
      );

  MediaDetails _tvToDetails(TvDetailsDto dto, {bool comingSoon = false}) {
    final seasons = dto.seasons
        .where((s) => s.seasonNumber > 0 && (s.episodeCount ?? 0) > 0)
        .toList();
    return MediaDetails(
      id: dto.id,
      isTv: true,
      comingSoon: comingSoon,
      title: dto.name ?? '',
      tagline: (dto.tagline?.isNotEmpty ?? false) ? dto.tagline : null,
      overview: dto.overview ?? '',
      backdropPath: dto.backdropPath,
      posterPath: dto.posterPath,
      year: _year(dto.firstAirDate),
      rating: dto.voteAverage ?? 0,
      runtimeMinutes:
          dto.episodeRunTime.isNotEmpty ? dto.episodeRunTime.first : null,
      language: languageName(dto.originalLanguage),
      genres: dto.genres
          .map((g) => g.name ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
      cast: (dto.credits?.cast ?? const []).take(12).toList(),
      trailerKey: dto.videos?.bestTrailerKey(),
      numberOfSeasons: dto.numberOfSeasons ?? seasons.length,
      seasons: seasons,
      releaseDate: dto.firstAirDate,
    );
  }

  String? _year(String? date) =>
      (date != null && date.length >= 4) ? date.substring(0, 4) : null;

  // ---- Episode segments (recap / intro / outro) --------------------------

  final Map<int, String?> _imdbCache = {};
  final Map<String, MediaSegments?> _segmentCache = {};

  /// The series' IMDb id (from TMDB external_ids), cached. introdb keys on it.
  Future<String?> seriesImdbId(int tvId) async {
    if (_imdbCache.containsKey(tvId)) return _imdbCache[tvId];
    String? imdb;
    try {
      imdb = await _api.tvImdbId(tvId);
    } catch (_) {
      imdb = null;
    }
    _imdbCache[tvId] = imdb;
    return imdb;
  }

  /// Recap / intro / outro timings for a TV episode, or null if unavailable.
  Future<MediaSegments?> episodeSegments(
    int tvId,
    int season,
    int episode,
  ) async {
    final key = '$tvId-$season-$episode';
    if (_segmentCache.containsKey(key)) return _segmentCache[key];
    final imdb = await seriesImdbId(tvId);
    MediaSegments? seg;
    if (imdb != null && imdb.isNotEmpty) {
      seg = await _introDb.segments(imdb, season, episode);
    }
    _segmentCache[key] = seg;
    return seg;
  }

  // ---- Streaming ---------------------------------------------------------

  Future<ExtractResponse> streamSource(
    String type,
    int tmdbId, {
    int? season,
    int? episode,
  }) =>
      _stream.extract(tmdbId, type, season: season, episode: episode);

  // ---- Personalization ---------------------------------------------------

  /// Recommendations from watch history + search seeds. [scope] is 'home',
  /// 'movie', or 'tv'. Ranks by how many seeds surfaced each item, then rating.
  Future<List<MediaItem>> recommended(String scope) async {
    final combined = <String, Seed>{};
    for (final w in WatchProgressStore.all()) {
      combined.putIfAbsent('${w.type}-${w.tmdbId}', () => Seed(w.type, w.tmdbId));
    }
    for (final s in RecommendationSeeds.all()) {
      combined.putIfAbsent('${s.type}-${s.id}', () => s);
    }

    var seeds = combined.values.toList();
    if (scope != 'home') {
      seeds = seeds.where((s) => s.type == scope).toList();
    }
    seeds = seeds.take(12).toList();
    if (seeds.isEmpty) return [];

    final exclude = combined.keys.toSet();
    final freq = <int, int>{};
    final byId = <int, MediaItem>{};

    for (final s in seeds) {
      final List<MediaItem> recs;
      try {
        recs = await similar(s.type, s.id);
      } catch (_) {
        continue;
      }
      for (final item in recs) {
        final t = item.resolvedType(s.type);
        if (exclude.contains('$t-${item.id}')) continue;
        if (scope != 'home' && t != scope) continue;
        freq[item.id] = (freq[item.id] ?? 0) + 1;
        byId[item.id] = item;
      }
    }

    final ranked = byId.values.toList()
      ..sort((a, b) {
        final byFreq = (freq[b.id] ?? 0).compareTo(freq[a.id] ?? 0);
        if (byFreq != 0) return byFreq;
        return (b.voteAverage ?? 0).compareTo(a.voteAverage ?? 0);
      });
    return ranked.take(rowLimit).toList();
  }

  /// Continue-watching entries, enriched with title/poster from cached details.
  ///
  /// Includes in-progress items, every TV series you've started (a finished
  /// episode advances the record to the next one — the series stays here), and
  /// fully-watched movies/series. `all()` already sorts completed titles to the
  /// end, so completed items sink to the bottom instead of disappearing.
  Future<List<WatchProgress>> continueWatching() async {
    final progs = WatchProgressStore.all()
        .where((p) => p.completed || p.isResumable || p.type == 'tv')
        .toList();
    final out = <WatchProgress>[];
    for (final p in progs) {
      final hasInfo = (p.title?.isNotEmpty ?? false) &&
          (p.posterPath?.isNotEmpty ?? false);
      if (hasInfo) {
        out.add(p);
        continue;
      }
      // Enrich missing title/poster from details, but never drop a continuable
      // entry just because the details fetch failed.
      try {
        final d = await details(p.type, p.tmdbId);
        out.add(p.copyWith(
          title: (p.title?.isNotEmpty ?? false) ? p.title : d.title,
          posterPath:
              (p.posterPath?.isNotEmpty ?? false) ? p.posterPath : d.posterPath,
        ));
      } catch (_) {
        out.add(p);
      }
    }
    return out;
  }
}

final mediaRepositoryProvider =
    Provider<MediaRepository>((ref) => MediaRepository());

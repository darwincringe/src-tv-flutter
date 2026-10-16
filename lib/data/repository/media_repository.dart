import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../helper/helper_query.dart';
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

  static const String netflix = '8';
  static const String region = 'PH';

  // Caches
  final Map<String, List<CategoryRow>> _pageCache = {};
  final Map<String, MediaDetails> _detailsCache = {};
  final Map<String, List<Episode>> _episodeCache = {};
  final Map<String, List<MediaItem>> _similarCache = {};
  final Map<String, List<MediaItem>> _searchCache = {};
  final Map<String, _HelperSession> _helperSessions = {};
  final Map<String, List<String>> _galleryCache = {};

  // ---- Row helpers -------------------------------------------------------

  List<MediaItem> _forRow(List<MediaItem> items) => items
      .where((i) => i.posterPath != null && i.posterPath!.isNotEmpty)
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
        final netflixRow = _interleave(netflixMovies, netflixTv);
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

  /// Official posters for the title. Empty when TMDB has none.
  Future<List<String>> gallery(String type, int id) async {
    final key = '$type-$id';
    final cached = _galleryCache[key];
    if (cached != null) return cached;
    final paths = await _api.posterGallery(type, id);
    _galleryCache[key] = paths;
    return paths;
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

  /// First 10 titles for a phrase such as "disturbing movies".
  /// A later [moreByDescription] call appends the next 10.
  Future<HelperFeed> findByDescription(String query) async {
    final key = query.toLowerCase().trim();
    if (key.isEmpty) return HelperFeed.empty;
    final request = parseHelperQuery(query);
    if (request == null) return HelperFeed.empty;
    final session = _HelperSession(this, request);
    _helperSessions[key] = session;
    return session.take(_HelperSession.batch);
  }

  /// The next 10 titles for the same phrase, after [findByDescription].
  Future<HelperFeed> moreByDescription(String query) async {
    final key = query.toLowerCase().trim();
    final session = _helperSessions[key];
    if (session == null) return findByDescription(query);
    return session.take(_HelperSession.batch);
  }

  Future<String?> _keywordIds(String? query) async {
    if (query == null || query.trim().isEmpty) return null;
    final found = await _api.searchKeywords(query);
    return pickKeywordIds(
      query,
      [for (final k in found) TmdbKeyword(k.id, k.name)],
    );
  }

  String? _joinKeywords(String? a, String? b) {
    if (a == null || a.isEmpty) return b;
    if (b == null || b.isEmpty) return a;
    return '$a,$b';
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
      // "Coming Soon" for movies = upcoming or released within the last 30 days.
      d = _movieToDetails(dto, comingSoon: isComingSoonRelease(dto.releaseDate));
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
    String? source,
  }) =>
      _stream.extract(
        tmdbId,
        type,
        season: season,
        episode: episode,
        source: source,
      );

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
    return ranked;
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
    // Always prefer the TMDB poster (portrait key art with the title on it):
    // some stored records carry a backdrop/hero path, which shows up in the row
    // as a title-less image. details() is cached, so this is cheap on repeat
    // loads; fetch concurrently so a cold load is ~one round-trip, not N.
    return Future.wait(progs.map((p) async {
      try {
        final d = await details(p.type, p.tmdbId);
        return p.copyWith(
          title: (p.title?.isNotEmpty ?? false) ? p.title : d.title,
          // d.posterPath is the titled poster; only fall back to the stored
          // path when TMDB has none, so we never drop the image entirely.
          posterPath: (d.posterPath?.isNotEmpty ?? false)
              ? d.posterPath
              : p.posterPath,
        );
      } catch (_) {
        // Never drop a continuable entry just because details failed.
        return p;
      }
    }));
  }
}

final mediaRepositoryProvider =
    Provider<MediaRepository>((ref) => MediaRepository());

/// Titles gathered so far for a helper phrase, and whether another batch exists.
class HelperFeed {
  const HelperFeed(this.items, {required this.hasMore});

  final List<MediaItem> items;
  final bool hasMore;

  static const empty = HelperFeed([], hasMore: false);
}

/// Walks TMDB page by page and hands the screen [batch] titles at a time.
class _HelperSession {
  _HelperSession(this._repo, this.request);

  static const int batch = 10;

  final MediaRepository _repo;
  final HelperRequest request;
  final List<MediaItem> shown = [];
  final List<MediaItem> pending = [];
  final List<MediaItem> _movieBuf = [];
  final List<MediaItem> _tvBuf = [];
  final Set<String> _seen = {};

  bool _prepared = false;
  String? _moodIds;
  String? _genreKeywordIds;
  int _moviePage = 0;
  int _tvPage = 0;
  bool _movieDone = false;
  bool _tvDone = false;
  int? _seedId;
  String? _seedType;
  int _likePage = 0;
  bool _likeDone = false;

  bool get _sourcesDone => request.isLike ? _likeDone : _movieDone && _tvDone;

  Future<HelperFeed> take(int count) async {
    await _prepare();
    var spins = 0;
    while (pending.length < count && !_sourcesDone && spins < 40) {
      final before = pending.length;
      final pagesBefore = _moviePage + _tvPage + _likePage;
      await _pull();
      spins++;
      if (pending.length == before &&
          _moviePage + _tvPage + _likePage == pagesBefore) {
        break;
      }
    }
    final n = math.min(count, pending.length);
    if (n > 0) {
      shown.addAll(pending.sublist(0, n));
      pending.removeRange(0, n);
    }
    return HelperFeed(
      List<MediaItem>.from(shown),
      hasMore: pending.isNotEmpty || !_sourcesDone,
    );
  }

  Future<void> _prepare() async {
    if (_prepared) return;
    _prepared = true;
    if (request.isLike) {
      final found = await _repo.search(request.likeTitle!);
      final wanted = found.where((item) {
        final type = item.resolvedType('movie');
        if (type == 'tv') return request.series;
        return request.movies;
      }).toList();
      if (wanted.isEmpty) {
        _likeDone = true;
        return;
      }
      final first = wanted.first;
      _seedType = first.resolvedType('movie');
      _seedId = first.id;
      return;
    }
    _moodIds = await _moodKeywordIds();
    final needsGenreKeyword = request.keywordQueries.isEmpty &&
        ((request.movies && request.movieGenreId == null) ||
            (request.series && request.tvGenreId == null));
    if (needsGenreKeyword) {
      _genreKeywordIds = await _repo._keywordIds(request.genreWord);
    }
    if (!request.movies || !_canQuery(request.movieGenreId)) _movieDone = true;
    if (!request.series || !_canQuery(request.tvGenreId)) _tvDone = true;
  }

  Future<String?> _moodKeywordIds() async {
    final queries = request.keywordQueries.isNotEmpty
        ? request.keywordQueries
        : [if (request.mood != null && request.mood!.isNotEmpty) request.mood!];
    final ids = <String>[];
    for (final query in queries) {
      final found = await _repo._keywordIds(query);
      if (found != null && found.isNotEmpty) ids.add(found);
    }
    if (ids.isEmpty) return null;
    return ids.join('|');
  }

  bool _canQuery(String? genreId) {
    final keywords = genreId == null
        ? _repo._joinKeywords(_moodIds, _genreKeywordIds)
        : _moodIds;
    return (genreId != null && genreId.isNotEmpty) ||
        (keywords != null && keywords.isNotEmpty) ||
        request.language != null ||
        request.yearFrom != null;
  }

  Future<void> _pull() async {
    if (request.isLike) {
      await _pullLike();
      return;
    }
    if (_movieBuf.isEmpty && !_movieDone) await _fetchSide('movie');
    if (_tvBuf.isEmpty && !_tvDone) await _fetchSide('tv');
    while (_movieBuf.isNotEmpty || _tvBuf.isNotEmpty) {
      if (_movieBuf.isNotEmpty) pending.add(_movieBuf.removeAt(0));
      if (_tvBuf.isNotEmpty) pending.add(_tvBuf.removeAt(0));
    }
  }

  Future<void> _fetchSide(String type) async {
    final movies = type == 'movie';
    if (movies ? _movieDone : _tvDone) return;
    final genreId = movies ? request.movieGenreId : request.tvGenreId;
    if (!_canQuery(genreId)) {
      if (movies) {
        _movieDone = true;
      } else {
        _tvDone = true;
      }
      return;
    }
    final pageNumber = movies ? ++_moviePage : ++_tvPage;
    final page = await _repo._api.discoverFiltered(
      type,
      genres: genreId,
      keywords: genreId == null
          ? _repo._joinKeywords(_moodIds, _genreKeywordIds)
          : _moodIds,
      language: request.language,
      yearFrom: request.yearFrom,
      yearTo: request.yearTo,
      page: pageNumber,
      withoutGenres: request.withoutGenres,
      minRating: request.minRating,
    );
    final buf = movies ? _movieBuf : _tvBuf;
    buf.addAll(_accept(page.items, type));
    if (page.isLast) {
      if (movies) {
        _movieDone = true;
      } else {
        _tvDone = true;
      }
    }
  }

  Future<void> _pullLike() async {
    if (_likeDone || _seedId == null || _seedType == null) {
      _likeDone = true;
      return;
    }
    final page = await _repo._api.recommendationsPage(
      _seedType!,
      _seedId!,
      ++_likePage,
    );
    pending.addAll(_accept(page.items, _seedType!));
    if (page.isLast) _likeDone = true;
  }

  List<MediaItem> _accept(List<MediaItem> items, String type) {
    final fresh = <MediaItem>[];
    for (final item in _repo._withPosters(_repo._tag(items, type))) {
      if (_seen.add('$type-${item.id}')) fresh.add(item);
    }
    return fresh;
  }
}

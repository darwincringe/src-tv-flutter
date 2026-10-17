import 'package:dio/dio.dart';

import '../models/details_dto.dart';
import '../models/media_item.dart';
import 'tmdb_client.dart';

/// One page of a TMDB list, plus how many pages exist after it.
class TmdbListPage {
  const TmdbListPage({
    required this.items,
    required this.page,
    required this.totalPages,
  });

  final List<MediaItem> items;
  final int page;
  final int totalPages;

  bool get isLast => items.isEmpty || page >= totalPages;
}

/// Thin wrapper over the TMDB v3 endpoints the app uses. Mirrors the 19
/// endpoints declared in the Kotlin `TmdbApi.kt`.
class TmdbApi {
  TmdbApi([Dio? dio]) : _dio = dio ?? TmdbClient.create();

  final Dio _dio;

  Future<List<MediaItem>> _list(
    String path, [
    Map<String, dynamic>? params,
  ]) async {
    final page = await _page(path, params);
    return page.items;
  }

  Future<TmdbListPage> _page(
    String path, [
    Map<String, dynamic>? params,
  ]) async {
    final resp = await _dio.get(path, queryParameters: params);
    final data = resp.data as Map<String, dynamic>;
    final results = (data['results'] as List?) ?? const [];
    return TmdbListPage(
      items: results
          .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      page: (data['page'] as num?)?.toInt() ?? 1,
      totalPages: (data['total_pages'] as num?)?.toInt() ?? 1,
    );
  }

  // Trending
  Future<List<MediaItem>> trendingAllWeek() => _list('trending/all/week');

  // Movies
  Future<List<MediaItem>> nowPlayingMovies() => _list('movie/now_playing');
  Future<List<MediaItem>> popularMovies() => _list('movie/popular');
  Future<List<MediaItem>> topRatedMovies() => _list('movie/top_rated');
  Future<List<MediaItem>> upcomingMovies() => _list('movie/upcoming');

  // TV
  Future<List<MediaItem>> popularTv() => _list('tv/popular');
  Future<List<MediaItem>> topRatedTv() => _list('tv/top_rated');
  Future<List<MediaItem>> airingTodayTv() => _list('tv/airing_today');
  Future<List<MediaItem>> onTheAirTv() => _list('tv/on_the_air');

  // Discover by genre
  Future<List<MediaItem>> discoverMovies(String genreIds) => _list(
        'discover/movie',
        {'with_genres': genreIds, 'sort_by': 'popularity.desc'},
      );

  Future<List<MediaItem>> discoverTv(String genreIds) => _list(
        'discover/tv',
        {'with_genres': genreIds, 'sort_by': 'popularity.desc'},
      );

  /// Free-form discover used by the content helper. [type] is `movie` or `tv`.
  Future<TmdbListPage> discoverFiltered(
    String type, {
    String? genres,
    String? keywords,
    String? language,
    int? yearFrom,
    int? yearTo,
    int page = 1,
    String? withoutGenres,
    double? minRating,
    int? personId,
    String? personRole,
  }) {
    final params = <String, dynamic>{
      'sort_by': 'popularity.desc',
      'vote_count.gte': 40,
      'include_adult': false,
      'page': page,
    };
    if (genres != null && genres.isNotEmpty) params['with_genres'] = genres;
    if (withoutGenres != null && withoutGenres.isNotEmpty) {
      params['without_genres'] = withoutGenres;
    }
    if (minRating != null) params['vote_average.gte'] = minRating;
    if (keywords != null && keywords.isNotEmpty) {
      params['with_keywords'] = keywords;
    }
    if (personId != null) {
      final key = type == 'tv'
          ? 'with_people'
          : personRole == 'crew'
              ? 'with_crew'
              : 'with_cast';
      params[key] = personId;
    }
    if (language != null && language.isNotEmpty) {
      params['with_original_language'] = language;
    }
    if (type == 'movie') {
      if (yearFrom != null) {
        params['primary_release_date.gte'] = '$yearFrom-01-01';
      }
      if (yearTo != null) {
        params['primary_release_date.lte'] = '$yearTo-12-31';
      }
    } else {
      if (yearFrom != null) params['first_air_date.gte'] = '$yearFrom-01-01';
      if (yearTo != null) params['first_air_date.lte'] = '$yearTo-12-31';
    }
    return _page('discover/$type', params);
  }

  /// Recommendations for one title, one TMDB page at a time.
  Future<TmdbListPage> recommendationsPage(String type, int id, int page) =>
      _page('$type/$id/recommendations', {'page': page});

  /// Official posters only. Scene stills and backdrops are left out so the
  /// gallery does not spoil the story.
  Future<List<String>> posterGallery(String type, int id) async {
    final resp = await _dio.get('$type/$id/images');
    final data = resp.data as Map<String, dynamic>;
    final raw = (data['posters'] as List?) ?? const [];
    final ranked = <({String path, int votes, bool safe})>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final path = item['file_path'] as String?;
      if (path == null || path.isEmpty) continue;
      final width = (item['width'] as num?)?.toInt() ?? 0;
      if (width > 0 && width < 300) continue;
      final lang = item['iso_639_1'] as String?;
      final safe = lang == null || lang.isEmpty || lang == 'en';
      ranked.add((
        path: path,
        votes: (item['vote_count'] as num?)?.toInt() ?? 0,
        safe: safe,
      ));
    }
    ranked.sort((a, b) {
      if (a.safe != b.safe) return a.safe ? -1 : 1;
      return b.votes.compareTo(a.votes);
    });
    final seen = <String>{};
    final out = <String>[];
    for (final poster in ranked.where((p) => p.safe)) {
      if (seen.add(poster.path)) out.add(poster.path);
      if (out.length == 12) return out;
    }
    for (final poster in ranked) {
      if (seen.add(poster.path)) out.add(poster.path);
      if (out.length == 12) break;
    }
    return out;
  }

  Future<List<({int id, String name, String department, double popularity})>>
      searchPeople(String query) async {
    final resp = await _dio.get(
      'search/person',
      queryParameters: {'query': query},
    );
    final data = resp.data as Map<String, dynamic>;
    final results = (data['results'] as List?) ?? const [];
    return [
      for (final raw in results)
        if (raw is Map)
          (
            id: (raw['id'] as num).toInt(),
            name: (raw['name'] as String?) ?? '',
            department: (raw['known_for_department'] as String?) ?? '',
            popularity: (raw['popularity'] as num?)?.toDouble() ?? 0,
          ),
    ];
  }

  Future<List<({int id, String name})>> searchKeywords(String query) async {
    final resp = await _dio.get(
      'search/keyword',
      queryParameters: {'query': query},
    );
    final data = resp.data as Map<String, dynamic>;
    final results = (data['results'] as List?) ?? const [];
    return [
      for (final raw in results)
        if (raw is Map)
          (
            id: (raw['id'] as num).toInt(),
            name: (raw['name'] as String?) ?? '',
          ),
    ];
  }

  // Discover by watch provider
  Future<List<MediaItem>> discoverMoviesByProvider(
    String providerId,
    String region,
  ) =>
      _list('discover/movie', {
        'with_watch_providers': providerId,
        'watch_region': region,
        'sort_by': 'popularity.desc',
      });

  Future<List<MediaItem>> discoverTvByProvider(
    String providerId,
    String region,
  ) =>
      _list('discover/tv', {
        'with_watch_providers': providerId,
        'watch_region': region,
        'sort_by': 'popularity.desc',
      });

  // Recommendations
  Future<List<MediaItem>> movieRecommendations(int id) =>
      _list('movie/$id/recommendations');
  Future<List<MediaItem>> tvRecommendations(int id) =>
      _list('tv/$id/recommendations');

  // Search
  Future<List<MediaItem>> searchMulti(String query) =>
      _list('search/multi', {'query': query});

  // Details
  Future<MovieDetailsDto> movieDetails(int id) async {
    final resp = await _dio.get(
      'movie/$id',
      queryParameters: {'append_to_response': 'credits,videos'},
    );
    return MovieDetailsDto.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<TvDetailsDto> tvDetails(int id) async {
    final resp = await _dio.get(
      'tv/$id',
      queryParameters: {'append_to_response': 'credits,videos'},
    );
    return TvDetailsDto.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<SeasonDetailsDto> seasonDetails(int id, int seasonNumber) async {
    final resp = await _dio.get('tv/$id/season/$seasonNumber');
    return SeasonDetailsDto.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Watch-provider payload for [id] (`results` keyed by country).
  Future<Object?> movieWatchProviders(int id) async {
    final resp = await _dio.get('movie/$id/watch/providers');
    return resp.data;
  }

  /// Release-date payload for [id], including theatrical vs digital types.
  Future<Object?> movieReleaseDates(int id) async {
    final resp = await _dio.get('movie/$id/release_dates');
    return resp.data;
  }

  /// Whether the movie has any watch provider (stream/rent/buy/free/ads) in
  /// [region].
  Future<bool> movieHasProviders(int id, String region) async {
    final resp = await _dio.get('movie/$id/watch/providers');
    final data = resp.data;
    if (data is! Map) return false;
    final results = data['results'];
    if (results is! Map) return false;
    final r = results[region];
    if (r is! Map) return false;
    for (final key in const ['flatrate', 'rent', 'buy', 'free', 'ads']) {
      final list = r[key];
      if (list is List && list.isNotEmpty) return true;
    }
    return false;
  }

  /// The series' IMDb id (e.g. "tt1190634"), used to look up recap/intro/outro
  /// timings on introdb. Null if TMDB has none.
  Future<String?> tvImdbId(int id) async {
    final resp = await _dio.get('tv/$id/external_ids');
    final data = resp.data;
    if (data is Map && data['imdb_id'] is String) {
      return data['imdb_id'] as String;
    }
    return null;
  }
}

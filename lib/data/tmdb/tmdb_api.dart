import 'package:dio/dio.dart';

import '../models/details_dto.dart';
import '../models/media_item.dart';
import 'tmdb_client.dart';

/// Thin wrapper over the TMDB v3 endpoints the app uses. Mirrors the 19
/// endpoints declared in the Kotlin `TmdbApi.kt`.
class TmdbApi {
  TmdbApi([Dio? dio]) : _dio = dio ?? TmdbClient.create();

  final Dio _dio;

  Future<List<MediaItem>> _list(
    String path, [
    Map<String, dynamic>? params,
  ]) async {
    final resp = await _dio.get(path, queryParameters: params);
    final data = resp.data as Map<String, dynamic>;
    final results = (data['results'] as List?) ?? const [];
    return results
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
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

  /// Whether the movie has any watch provider (stream/rent/buy/free/ads) in
  /// [region]. When false we tag the title "Coming Soon".
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

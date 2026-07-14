import 'package:dio/dio.dart';

import 'extract_response.dart';

/// Client for the self-hosted extract backend. Mirrors `StreamApi.kt`.
/// Uses cleartext HTTP (permitted on Android via usesCleartextTraffic and on
/// iOS via an ATS exception).
class StreamClient {
  static const String baseUrl = 'http://165.22.111.114:4000/';

  StreamClient([Dio? dio])
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

  final Dio _dio;

  Future<ExtractResponse> extract(
    int tmdbId,
    String type, {
    int? season,
    int? episode,
  }) async {
    final params = <String, dynamic>{'tmdb_id': tmdbId, 'type': type};
    if (season != null) params['season'] = season;
    if (episode != null) params['episode'] = episode;
    final resp = await _dio.get('extract', queryParameters: params);
    final data = resp.data;
    if (data is Map<String, dynamic>) return ExtractResponse.fromJson(data);
    return const ExtractResponse(success: false, error: 'Bad response');
  }
}

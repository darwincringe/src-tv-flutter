import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'extract_response.dart';

/// Client for the self-hosted extract backend. Mirrors `StreamApi.kt`.
class StreamClient {
  /// HTTPS endpoint (behind nginx + Let's Encrypt on the droplet).
  static const String baseUrl = 'https://api.srctv.space/';

  /// Set at startup so extract and the other locked routes can send
  /// `Authorization` without this file importing the auth service.
  static String? Function() bearerToken = () => null;

  static Map<String, String> authHeaders() {
    final token = bearerToken();
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  StreamClient([Dio? dio])
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 180),
                receiveTimeout: const Duration(seconds: 180),
              ),
            );

  final Dio _dio;

  // Our API host. The backend builds absolute URLs from the proxied request,
  // which reaches it as http (nginx -> node), so it emits http://<host>/... .
  // We upgrade those to https so the player never has to follow an http->https
  // redirect (ExoPlayer blocks cross-protocol redirects by default).
  static final String _host = Uri.parse(baseUrl).host;
  static final String _scheme = Uri.parse(baseUrl).scheme;

  String _upgrade(String url) => url.startsWith('http://$_host')
      ? url.replaceFirst('http://$_host', '$_scheme://$_host')
      : url;

  /// Subtitle URL adjusted for the current platform. On the WEB build, the
  /// backend's direct links are CORS-blocked by the browser, so route them
  /// through `/wyzie-subtitle-srt`. Subtitles already on our host, and all
  /// native builds, pass through unchanged. A `release` label stays visible
  /// to the player either as a real query param or as the source's `&release=`
  /// suffix.
  String _subtitleUrl(String url) {
    final upgraded = _upgrade(url);
    if (!kIsWeb) return upgraded;
    if (upgraded.startsWith('$_scheme://$_host')) return upgraded;
    var downloadUrl = upgraded;
    var releaseSuffix = '';
    final parsed = Uri.tryParse(upgraded);
    final queryRelease = parsed?.queryParameters['release']?.trim();
    if (queryRelease != null && queryRelease.isNotEmpty) {
      releaseSuffix = '&release=${Uri.encodeQueryComponent(queryRelease)}';
    } else if (!upgraded.contains('?')) {
      final m =
          RegExp(r'&release=(.+)$', caseSensitive: false).firstMatch(upgraded);
      if (m != null) {
        downloadUrl = upgraded.substring(0, m.start);
        releaseSuffix = upgraded.substring(m.start);
      }
    }
    return '${baseUrl}wyzie-subtitle-srt?url='
        '${Uri.encodeComponent(downloadUrl)}$releaseSuffix';
  }

  /// English Wyzie tracks only. Empty when Wyzie has no English release.
  Future<List<String>> wyzie(
    int tmdbId,
    String type, {
    int? season,
    int? episode,
  }) async {
    final params = <String, dynamic>{'tmdb_id': tmdbId, 'type': type};
    if (season != null) params['season'] = season;
    if (episode != null) params['episode'] = episode;
    final resp = await _dio.get(
      'wyzie',
      queryParameters: params,
      options: Options(headers: authHeaders()),
    );
    final data = resp.data;
    if (data is! Map) return const [];
    final raw = data['subtitles'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is String && item.isNotEmpty) _subtitleUrl(item),
    ];
  }

  /// One pinned provider from `GET /extract/vaplayer`.
  Future<ExtractResponse> extract(
    int tmdbId,
    String type, {
    int? season,
    int? episode,
    String? source,
  }) async {
    final params = <String, dynamic>{'tmdb_id': tmdbId, 'type': type};
    if (season != null) params['season'] = season;
    if (episode != null) params['episode'] = episode;
    if (source != null && source.isNotEmpty) params['source'] = source;
    final resp = await _dio.get(
      'extract/vaplayer',
      queryParameters: params,
      options: Options(headers: authHeaders()),
    );
    final data = resp.data;
    if (data is! Map) {
      return const ExtractResponse(success: false, error: 'Bad response');
    }
    final json = Map<String, dynamic>.from(data);
    final r = ExtractResponse.fromJson(json);
    final provider = json['source'];
    final quality = json['quality'];
    return ExtractResponse(
      success: r.success,
      hlsUrl: r.hlsUrl == null ? null : _upgrade(r.hlsUrl!),
      subtitles: r.subtitles.map(_subtitleUrl).toList(),
      error: r.error,
      source: provider is String ? provider : null,
      quality: quality is String ? quality : null,
      mirrors: _parseMirrors(json['mirrors']),
    );
  }

  List<StreamMirror> _parseMirrors(Object? raw) {
    if (raw is! List) return const [];
    final out = <StreamMirror>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final url = item['hls_url'];
      final source = item['source'];
      if (url is! String || url.isEmpty) continue;
      if (source is! String || source.isEmpty) continue;
      final quality = item['quality'];
      out.add(StreamMirror(
        hlsUrl: _upgrade(url),
        source: source,
        quality: quality is String ? quality.trim() : '',
      ));
    }
    return out;
  }
}

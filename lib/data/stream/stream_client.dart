import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'extract_response.dart';

/// Client for the self-hosted extract backend. Mirrors `StreamApi.kt`.
class StreamClient {
  /// HTTPS endpoint (behind nginx + Let's Encrypt on the droplet).
  static const String baseUrl = 'https://api.srctv.space/';

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
  /// backend's direct `dl.opensubtitles.org/...` links are CORS-blocked by the
  /// browser, so route them through our own `/wyzie-subtitle-srt` proxy (which
  /// carries CORS headers). Subtitles already on our host, and all native
  /// builds, pass through unchanged.
  String _subtitleUrl(String url) {
    final upgraded = _upgrade(url);
    if (!kIsWeb) return upgraded;
    if (upgraded.startsWith('$_scheme://$_host')) return upgraded; // already ours
    // Direct source links append "&release=..." as a NON-query suffix (see
    // subtitle_config.dart). Split it off so only the real download URL is
    // proxied; re-attach it as a query param after our proxy URL.
    var downloadUrl = upgraded;
    var releaseSuffix = '';
    if (!upgraded.contains('?')) {
      final m =
          RegExp(r'&release=(.+)$', caseSensitive: false).firstMatch(upgraded);
      if (m != null) {
        downloadUrl = upgraded.substring(0, m.start);
        releaseSuffix = upgraded.substring(m.start); // "&release=<encoded>"
      }
    }
    return '${baseUrl}wyzie-subtitle-srt?url='
        '${Uri.encodeComponent(downloadUrl)}$releaseSuffix';
  }

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
    if (data is! Map<String, dynamic>) {
      return const ExtractResponse(success: false, error: 'Bad response');
    }
    final r = ExtractResponse.fromJson(data);
    // Upgrade our-host URLs to https (external subtitle URLs are left as-is).
    return ExtractResponse(
      success: r.success,
      hlsUrl: r.hlsUrl == null ? null : _upgrade(r.hlsUrl!),
      subtitles: r.subtitles.map(_subtitleUrl).toList(),
      error: r.error,
    );
  }
}

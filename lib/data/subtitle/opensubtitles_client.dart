import 'package:dio/dio.dart';

import '../stream/stream_client.dart';

class OpenSubtitleHit {
  final String fileId;
  final String label;
  final String? language;
  final String detail;

  const OpenSubtitleHit({
    required this.fileId,
    required this.label,
    required this.detail,
    this.language,
  });
}

class OpenSubtitlesException implements Exception {
  final String message;
  const OpenSubtitlesException(this.message);
  @override
  String toString() => message;
}

/// Search and download through our API. The SRT route needs the same Bearer
/// token as `/extract`.
class OpenSubtitlesClient {
  OpenSubtitlesClient([Dio? dio])
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: StreamClient.baseUrl,
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

  final Dio _dio;

  Future<List<OpenSubtitleHit>> search({
    required String query,
    int? season,
    int? episode,
    int? tmdbId,
    String? type,
    String lang = 'en',
  }) async {
    final params = <String, dynamic>{
      'q': query,
      'lang': lang,
      'season': ?season,
      'episode': ?episode,
      'tmdb_id': ?tmdbId,
      'type': ?type,
    };
    try {
      final resp = await _dio.get<dynamic>(
        'opensubtitles/search',
        queryParameters: params,
        options: Options(headers: StreamClient.authHeaders()),
      );
      final data = resp.data;
      if (data is! Map) {
        throw const OpenSubtitlesException('Bad response from the server.');
      }
      if (data['success'] == false) {
        throw OpenSubtitlesException(
          data['error'] as String? ?? 'Search failed.',
        );
      }
      final raw = data['results'];
      if (raw is! List) return const [];
      final out = <OpenSubtitleHit>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final id = item['file_id'];
        if (id == null) continue;
        final fileId = id.toString();
        if (fileId.isEmpty) continue;
        final release = _text(item['release']) ?? _text(item['file_name']);
        final langName = _text(item['language']);
        final downloads = item['downloads'];
        final parts = <String>[
          ?langName,
          if (downloads is num && downloads > 0) '${downloads.toInt()} downloads',
          if (item['hearing_impaired'] == true) 'HI',
        ];
        out.add(OpenSubtitleHit(
          fileId: fileId,
          label: release ?? 'Subtitle',
          language: langName,
          detail: parts.join(' · '),
        ));
      }
      return out;
    } on OpenSubtitlesException {
      rethrow;
    } on DioException catch (e) {
      throw OpenSubtitlesException(_dioMessage(e));
    }
  }

  Future<String> downloadSrt(String fileId) async {
    try {
      final resp = await _dio.get<String>(
        'opensubtitles/srt',
        queryParameters: {'file_id': fileId},
        options: Options(
          headers: StreamClient.authHeaders(),
          responseType: ResponseType.plain,
        ),
      );
      final body = resp.data ?? '';
      if (body.trim().isEmpty) {
        throw const OpenSubtitlesException('That subtitle file was empty.');
      }
      return body;
    } on OpenSubtitlesException {
      rethrow;
    } on DioException catch (e) {
      throw OpenSubtitlesException(_dioMessage(e));
    }
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _dioMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
    if (data is String && data.trim().isNotEmpty) {
      final line = data.trim();
      return line.length > 180 ? line.substring(0, 180) : line;
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Cannot reach the server. Check your connection.';
    }
    return 'Subtitle search failed.';
  }
}

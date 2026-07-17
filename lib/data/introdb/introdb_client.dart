import 'package:dio/dio.dart';

/// A timed segment of an episode (recap / intro / outro), in milliseconds.
class Segment {
  final int startMs;
  final int endMs;
  const Segment(this.startMs, this.endMs);
}

/// Recap / intro / outro segments for one episode, from introdb.app.
class MediaSegments {
  final Segment? recap;
  final Segment? intro;
  final Segment? outro;
  const MediaSegments({this.recap, this.intro, this.outro});

  bool get isEmpty => recap == null && intro == null && outro == null;
}

/// Client for the free introdb.app API, which returns crowd-sourced recap /
/// intro / outro timings keyed by the series IMDb id + season + episode. Used
/// to power the Skip Recap / Skip Intro / Next Episode buttons.
class IntroDbClient {
  IntroDbClient([Dio? dio]) : _dio = dio ?? Dio();
  final Dio _dio;

  static const _base = 'https://api.introdb.app/segments';

  Future<MediaSegments?> segments(
    String imdbId,
    int season,
    int episode,
  ) async {
    try {
      final resp = await _dio.get<dynamic>(
        _base,
        queryParameters: {
          'imdb_id': imdbId,
          'season': season,
          'episode': episode,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      final data = resp.data;
      if (data is! Map) return null;
      final seg = MediaSegments(
        recap: _parse(data['recap']),
        intro: _parse(data['intro']),
        outro: _parse(data['outro']),
      );
      return seg.isEmpty ? null : seg;
    } catch (_) {
      return null;
    }
  }

  Segment? _parse(dynamic s) {
    if (s is Map && s['start_ms'] is num && s['end_ms'] is num) {
      return Segment(
        (s['start_ms'] as num).toInt(),
        (s['end_ms'] as num).toInt(),
      );
    }
    return null;
  }
}

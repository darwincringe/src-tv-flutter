import 'package:shared_preferences/shared_preferences.dart';

/// Caption delay for one movie, or one TV episode, on this device only.
/// Positive means the captions appear later. Negative means they appear earlier.
class SubtitleOffsetStore {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String _key(
    String type,
    int tmdbId,
    int? season,
    int? episode,
  ) =>
      type == 'tv'
          ? 'suboffset_tv-$tmdbId-s${season ?? 0}e${episode ?? 0}'
          : 'suboffset_movie-$tmdbId';

  static int get(
    String type,
    int tmdbId,
    int? season,
    int? episode,
  ) =>
      _prefs.getInt(_key(type, tmdbId, season, episode)) ?? 0;

  static Future<void> save(
    String type,
    int tmdbId,
    int? season,
    int? episode,
    int offsetMs,
  ) async {
    await _prefs.setInt(_key(type, tmdbId, season, episode), offsetMs);
  }
}

/// `0s`, `+1s`, `+0.5s`, `-1.5s`.
String formatSubtitleOffset(int offsetMs) {
  if (offsetMs == 0) return '0s';
  final negative = offsetMs < 0;
  final abs = offsetMs.abs();
  final whole = abs ~/ 1000;
  final tenth = (abs % 1000) ~/ 100;
  final body = tenth == 0 ? '$whole' : '$whole.$tenth';
  return negative ? '-${body}s' : '+$body' 's';
}

import 'package:shared_preferences/shared_preferences.dart';

/// The mirror a user last picked, kept on this device only.
///
/// Movies are stored per title. A TV show is stored per season, so the source
/// chosen on any episode is used for the other episodes of that season.
class MirrorPrefStore {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String _key(String type, int tmdbId, int? season) => type == 'tv'
      ? 'mirrorpref_tv-$tmdbId-s${season ?? 0}'
      : 'mirrorpref_$type-$tmdbId';

  /// Older builds stored one source for the whole series.
  static String _seriesKey(String type, int tmdbId) =>
      'mirrorpref_$type-$tmdbId';

  static String? get(String type, int tmdbId, [int? season]) {
    final value = _prefs.getString(_key(type, tmdbId, season));
    if (value != null && value.isNotEmpty) return value;
    if (type != 'tv') return null;
    final series = _prefs.getString(_seriesKey(type, tmdbId));
    if (series == null || series.isEmpty) return null;
    return series;
  }

  static Future<void> save(
    String type,
    int tmdbId,
    String source, [
    int? season,
  ]) {
    return _prefs.setString(_key(type, tmdbId, season), source);
  }
}

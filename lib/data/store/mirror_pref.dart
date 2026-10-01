import 'package:shared_preferences/shared_preferences.dart';

/// The mirror a user last picked, kept on this device only.
///
/// Movies are stored per title. A TV show is stored once for the whole series,
/// so the source chosen on any episode is used for every season.
class MirrorPrefStore {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String _key(String type, int tmdbId) => 'mirrorpref_$type-$tmdbId';

  static String? get(String type, int tmdbId) {
    final value = _prefs.getString(_key(type, tmdbId));
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static Future<void> save(String type, int tmdbId, String source) {
    return _prefs.setString(_key(type, tmdbId), source);
  }
}

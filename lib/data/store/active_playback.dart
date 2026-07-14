import 'package:shared_preferences/shared_preferences.dart';

/// Pointer to the stream currently (or last) playing, so the app can jump
/// straight back into the player on resume. Mirrors the Kotlin `ActivePlayback`.
class ActivePlayback {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static void save({
    required int tmdbId,
    required String type,
    int? season,
    int? episode,
  }) {
    _prefs.setBool('ap_active', true);
    _prefs.setInt('ap_tmdb', tmdbId);
    _prefs.setString('ap_type', type);
    _prefs.setInt('ap_season', season ?? -1);
    _prefs.setInt('ap_episode', episode ?? -1);
  }

  static void clear() => _prefs.setBool('ap_active', false);

  static bool isActive() => _prefs.getBool('ap_active') ?? false;
  static int tmdbId() => _prefs.getInt('ap_tmdb') ?? 0;
  static String type() => _prefs.getString('ap_type') ?? 'movie';
  static int season() => _prefs.getInt('ap_season') ?? -1;
  static int episode() => _prefs.getInt('ap_episode') ?? -1;
}

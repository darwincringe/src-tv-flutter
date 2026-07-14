import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A remembered subtitle choice. [off] means the user turned subtitles off.
class SubtitlePref {
  final String? name;
  final String? language;
  final bool off;

  const SubtitlePref({this.name, this.language, this.off = false});

  Map<String, dynamic> toJson() => {'name': name, 'lang': language, 'off': off};

  factory SubtitlePref.fromJson(Map<String, dynamic> j) => SubtitlePref(
        name: j['name'] as String?,
        language: j['lang'] as String?,
        off: (j['off'] as bool?) ?? false,
      );
}

/// Persists the user's subtitle choice so it's reapplied next time. Movies are
/// keyed per title; TV shows are keyed per season, so picking a subtitle on one
/// episode carries to the other episodes of that season.
class SubtitlePrefStore {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String _key(String type, int tmdbId, int? season) => type == 'tv'
      ? 'subpref_tv-$tmdbId-s${season ?? 0}'
      : 'subpref_movie-$tmdbId';

  static void save(String type, int tmdbId, int? season, SubtitlePref pref) {
    _prefs.setString(_key(type, tmdbId, season), jsonEncode(pref.toJson()));
  }

  static SubtitlePref? get(String type, int tmdbId, int? season) {
    final s = _prefs.getString(_key(type, tmdbId, season));
    if (s == null) return null;
    try {
      return SubtitlePref.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

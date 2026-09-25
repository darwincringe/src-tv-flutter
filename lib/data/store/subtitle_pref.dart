import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A remembered subtitle choice. [off] means the user turned subtitles off.
class SubtitlePref {
  final String? name;
  final String? language;
  final bool off;

  /// When true, the web player shifts this track so caption timing lines up
  /// with the video's audio. [offsetMs] is the last shift it found.
  final bool autoSync;
  final int offsetMs;

  const SubtitlePref({
    this.name,
    this.language,
    this.off = false,
    this.autoSync = false,
    this.offsetMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'lang': language,
        'off': off,
        'autoSync': autoSync,
        'offsetMs': offsetMs,
      };

  factory SubtitlePref.fromJson(Map<String, dynamic> j) => SubtitlePref(
        name: j['name'] as String?,
        language: j['lang'] as String?,
        off: (j['off'] as bool?) ?? false,
        autoSync: (j['autoSync'] as bool?) ?? false,
        offsetMs: (j['offsetMs'] as num?)?.toInt() ?? 0,
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

  static Future<void> save(
    String type,
    int tmdbId,
    int? season,
    SubtitlePref pref,
  ) {
    return _prefs.setString(_key(type, tmdbId, season), jsonEncode(pref.toJson()));
  }

  static SubtitlePref? get(String type, int tmdbId, int? season) {
    final s = _prefs.getString(_key(type, tmdbId, season));
    if (s == null) return null;
    try {
      final decoded = jsonDecode(s);
      if (decoded is! Map) return null;
      return SubtitlePref.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}

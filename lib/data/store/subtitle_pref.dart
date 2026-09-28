import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A remembered subtitle choice. [off] means the user turned subtitles off.
class SubtitlePref {
  final String? name;
  final String? language;
  final bool off;

  /// When true, the player shifts this track so caption timing lines up with
  /// the video. [offsetMs] is the last shift it found (positive = show cues
  /// earlier). [updatedAt] is epoch millis for cross-device last-write-wins.
  final bool autoSync;
  final int offsetMs;
  final int updatedAt;

  const SubtitlePref({
    this.name,
    this.language,
    this.off = false,
    this.autoSync = true,
    this.offsetMs = 0,
    this.updatedAt = 0,
  });

  SubtitlePref stamped() => updatedAt > 0
      ? this
      : SubtitlePref(
          name: name,
          language: language,
          off: off,
          autoSync: autoSync,
          offsetMs: offsetMs,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );

  Map<String, dynamic> toJson() => {
        'name': name,
        'lang': language,
        'off': off,
        'autoSync': autoSync,
        'offsetMs': offsetMs,
        'updatedAt': updatedAt,
      };

  factory SubtitlePref.fromJson(Map<String, dynamic> j) => SubtitlePref(
        name: j['name'] as String?,
        language: j['lang'] as String?,
        off: (j['off'] as bool?) ?? false,
        autoSync: (j['autoSync'] as bool?) ?? true,
        offsetMs: (j['offsetMs'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

/// One stored choice plus the title it belongs to. Movies ignore [season].
class SubtitlePrefEntry {
  final String type;
  final int tmdbId;
  final int? season;
  final SubtitlePref pref;

  const SubtitlePrefEntry({
    required this.type,
    required this.tmdbId,
    required this.season,
    required this.pref,
  });
}

/// Persists the user's subtitle choice so it's reapplied next time. Movies are
/// keyed per title; TV shows are keyed per season, so picking a subtitle on one
/// episode carries to the other episodes of that season.
class SubtitlePrefStore {
  static late SharedPreferences _prefs;

  /// Bumped on every save so an open player can pick up a choice that just
  /// arrived from another device.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Fired after a local write. [SyncService] pushes it to the account.
  static void Function(String type, int tmdbId, int? season, SubtitlePref pref)?
      onSaved;

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
  ) async {
    final stamped = pref.stamped();
    await _prefs.setString(
      _key(type, tmdbId, season),
      jsonEncode(stamped.toJson()),
    );
    revision.value++;
    onSaved?.call(type, tmdbId, season, stamped);
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

  static final RegExp _tvKey = RegExp(r'^subpref_tv-(\d+)-s(\d+)$');
  static final RegExp _movieKey = RegExp(r'^subpref_movie-(\d+)$');

  /// Every saved choice on this device, for the account upload.
  static List<SubtitlePrefEntry> all() {
    final out = <SubtitlePrefEntry>[];
    for (final key in _prefs.getKeys()) {
      final tv = _tvKey.firstMatch(key);
      if (tv != null) {
        final pref = get('tv', int.parse(tv.group(1)!), int.parse(tv.group(2)!));
        if (pref != null) {
          out.add(SubtitlePrefEntry(
            type: 'tv',
            tmdbId: int.parse(tv.group(1)!),
            season: int.parse(tv.group(2)!),
            pref: pref,
          ));
        }
        continue;
      }
      final movie = _movieKey.firstMatch(key);
      if (movie == null) continue;
      final id = int.parse(movie.group(1)!);
      final pref = get('movie', id, null);
      if (pref != null) {
        out.add(SubtitlePrefEntry(
          type: 'movie',
          tmdbId: id,
          season: null,
          pref: pref,
        ));
      }
    }
    return out;
  }
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-title playback progress. Mirrors the Kotlin `WatchProgress` +
/// `WatchProgressStore`.
class WatchProgress {
  final int tmdbId;
  final String type; // 'movie' | 'tv'
  final int? season;
  final int? episode;
  final int positionMs;
  final int durationMs;
  final int updatedAt; // epoch millis
  final String? title;
  final String? posterPath;
  final bool completed;

  const WatchProgress({
    required this.tmdbId,
    required this.type,
    this.season,
    this.episode,
    this.positionMs = 0,
    this.durationMs = 0,
    this.updatedAt = 0,
    this.title,
    this.posterPath,
    this.completed = false,
  });

  /// Far enough in to resume, but not within 10s of the end.
  bool get isResumable =>
      positionMs > 5000 && positionMs < durationMs - 10000;

  /// Shown in Continue Watching: not finished, and either resumable or a TV
  /// record queued at the start of the next episode (position 0).
  bool get isContinuable =>
      !completed && (isResumable || (type == 'tv' && positionMs == 0));

  double get watchedFraction =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  WatchProgress copyWith({
    int? season,
    int? episode,
    int? positionMs,
    int? durationMs,
    int? updatedAt,
    String? title,
    String? posterPath,
    bool? completed,
  }) =>
      WatchProgress(
        tmdbId: tmdbId,
        type: type,
        season: season ?? this.season,
        episode: episode ?? this.episode,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        updatedAt: updatedAt ?? this.updatedAt,
        title: title ?? this.title,
        posterPath: posterPath ?? this.posterPath,
        completed: completed ?? this.completed,
      );

  Map<String, dynamic> toJson() => {
        'tmdbId': tmdbId,
        'type': type,
        'season': season,
        'episode': episode,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt,
        'title': title,
        'posterPath': posterPath,
        'completed': completed,
      };

  factory WatchProgress.fromJson(Map<String, dynamic> j) => WatchProgress(
        tmdbId: j['tmdbId'] as int,
        type: j['type'] as String,
        season: j['season'] as int?,
        episode: j['episode'] as int?,
        positionMs: (j['positionMs'] as int?) ?? 0,
        durationMs: (j['durationMs'] as int?) ?? 0,
        updatedAt: (j['updatedAt'] as int?) ?? 0,
        title: j['title'] as String?,
        posterPath: j['posterPath'] as String?,
        completed: (j['completed'] as bool?) ?? false,
      );
}

class WatchProgressStore {
  static const String _prefix = 'wp_';
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String _key(String type, int tmdbId) => '$_prefix$type-$tmdbId';

  static void save(WatchProgress p) {
    _prefs.setString(_key(p.type, p.tmdbId), jsonEncode(p.toJson()));
  }

  static WatchProgress? get(String type, int tmdbId) {
    final s = _prefs.getString(_key(type, tmdbId));
    if (s == null) return null;
    try {
      return WatchProgress.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static void remove(String type, int tmdbId) {
    _prefs.remove(_key(type, tmdbId));
  }

  /// All records, active (not completed) first by most-recent, then completed
  /// by most-recent. Mirrors `WatchProgressStore.all()`.
  static List<WatchProgress> all() {
    final items = _prefs
        .getKeys()
        .where((k) => k.startsWith(_prefix))
        .map((k) {
          final s = _prefs.getString(k);
          if (s == null) return null;
          try {
            return WatchProgress.fromJson(
              jsonDecode(s) as Map<String, dynamic>,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<WatchProgress>()
        .toList();

    items.sort((a, b) {
      if (a.completed != b.completed) return a.completed ? 1 : -1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return items;
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 95% of the runtime counts as watched. Once reached, it stays watched.
const double watchedFractionThreshold = 0.95;

/// True when [positionMs] is at least 95% of [durationMs].
bool reachedWatchedThreshold(int positionMs, int durationMs) =>
    durationMs > 0 && positionMs / durationMs >= watchedFractionThreshold;

/// Key for one episode inside a series progress record.
String watchedEpisodeKey(int season, int episode) => '$season-$episode';

/// Keeps a watched mark that was already earned. [next] is the new resume
/// point (often 50% on a rewatch). [previous] is the record already stored.
/// [finishedSeason] and [finishedEpisode] mark an episode that just ended
/// when [next] is the following episode queued at the start.
WatchProgress retainWatched(
  WatchProgress next, {
  WatchProgress? previous,
  int? finishedSeason,
  int? finishedEpisode,
}) {
  final seen = <String>{
    ...?previous?.watchedEpisodes,
    ...next.watchedEpisodes,
  };
  void addEpisode(int? season, int? episode) {
    if (season == null || episode == null) return;
    seen.add(watchedEpisodeKey(season, episode));
  }

  if (next.type == 'tv') {
    addEpisode(finishedSeason, finishedEpisode);
    if (previous != null && previous.completed) {
      addEpisode(previous.season, previous.episode);
    }
    if (next.completed ||
        reachedWatchedThreshold(next.positionMs, next.durationMs)) {
      addEpisode(next.season, next.episode);
    }
  }

  final movieWatched = next.type != 'tv' &&
      (next.watched ||
          next.completed ||
          (previous?.watched ?? false) ||
          (previous?.completed ?? false) ||
          reachedWatchedThreshold(next.positionMs, next.durationMs));

  return WatchProgress(
    tmdbId: next.tmdbId,
    type: next.type,
    season: next.season,
    episode: next.episode,
    positionMs: next.positionMs,
    durationMs: next.durationMs,
    updatedAt: next.updatedAt,
    title: next.title,
    posterPath: next.posterPath,
    completed: next.completed,
    watched: movieWatched,
    watchedEpisodes: seen.toList(),
  );
}

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

  /// Movie reached 95% at least once. Stays true through a rewatch.
  final bool watched;

  /// Episodes of a series that reached 95% at least once (`season-episode`).
  final List<String> watchedEpisodes;

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
    this.watched = false,
    this.watchedEpisodes = const [],
  });

  /// Far enough in to resume, but not within 10s of the end.
  bool get isResumable =>
      positionMs > 5000 && positionMs < durationMs - 10000;

  /// Shown in Continue Watching and as Resume. A series stays here until the
  /// last episode actually finishes — closing during the credits of one
  /// episode (inside the last 10s, so [isResumable] is false) still counts.
  bool get isContinuable =>
      !completed &&
      (isResumable || (type == 'tv' && (positionMs == 0 || positionMs > 5000)));

  double get watchedFraction =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  /// Show the watched check on a movie poster. True after 95%, including a
  /// rewatch that is currently earlier in the file.
  bool get isMovieWatched =>
      type != 'tv' &&
      (watched ||
          completed ||
          reachedWatchedThreshold(positionMs, durationMs));

  /// Show the watched check on this episode.
  bool isEpisodeWatched(int season, int episode) {
    if (type != 'tv') return false;
    if (watchedEpisodes.contains(watchedEpisodeKey(season, episode))) {
      return true;
    }
    if (this.season == season && this.episode == episode) {
      return completed ||
          reachedWatchedThreshold(positionMs, durationMs);
    }
    return false;
  }

  WatchProgress copyWith({
    int? season,
    int? episode,
    int? positionMs,
    int? durationMs,
    int? updatedAt,
    String? title,
    String? posterPath,
    bool? completed,
    bool? watched,
    List<String>? watchedEpisodes,
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
        watched: watched ?? this.watched,
        watchedEpisodes: watchedEpisodes ?? this.watchedEpisodes,
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
        'watched': watched,
        'watchedEpisodes': watchedEpisodes,
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
        watched: (j['watched'] as bool?) ?? false,
        watchedEpisodes: [
          for (final e in (j['watchedEpisodes'] as List?) ?? const [])
            e.toString(),
        ],
      );
}

class WatchProgressStore {
  static const String _prefix = 'wp_';
  static late SharedPreferences _prefs;
  static bool _ready = false;

  /// Bumped whenever progress changes so screens (e.g. Continue Watching) can
  /// refresh even after in-app navigation back from the player — which, unlike
  /// backgrounding the app, doesn't fire an app-resume lifecycle event.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Optional sync hooks, set by SyncService once accounts land. Fired AFTER a
  /// local write so a signed-in user's change can be pushed to their account.
  /// Null (no-op) when signed out or before SyncService.init().
  static void Function(WatchProgress p)? onSaved;
  static void Function(String type, int tmdbId)? onRemoved;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _ready = true;
  }

  static bool get isReady => _ready;

  static String _key(String type, int tmdbId) => '$_prefix$type-$tmdbId';

  static void save(
    WatchProgress p, {
    int? finishedSeason,
    int? finishedEpisode,
  }) {
    final stored = retainWatched(
      p,
      previous: get(p.type, p.tmdbId),
      finishedSeason: finishedSeason,
      finishedEpisode: finishedEpisode,
    );
    _prefs.setString(_key(stored.type, stored.tmdbId), jsonEncode(stored.toJson()));
    revision.value++;
    onSaved?.call(stored);
  }

  /// Mark a movie watched without moving its resume point.
  static void rememberMovie(String type, int tmdbId) {
    final prev = get(type, tmdbId);
    if (prev != null && (prev.watched || prev.completed)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    save(
      prev?.copyWith(updatedAt: now, watched: true) ??
          WatchProgress(
            tmdbId: tmdbId,
            type: type,
            updatedAt: now,
            watched: true,
          ),
    );
  }

  /// Mark one episode watched without moving the series resume point.
  static void rememberEpisode(
    String type,
    int tmdbId,
    int season,
    int episode,
  ) {
    final prev = get(type, tmdbId);
    if (prev != null && prev.isEpisodeWatched(season, episode)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    save(
      prev?.copyWith(updatedAt: now) ??
          WatchProgress(
            tmdbId: tmdbId,
            type: type,
            season: season,
            episode: episode,
            updatedAt: now,
          ),
      finishedSeason: season,
      finishedEpisode: episode,
    );
  }

  static WatchProgress? get(String type, int tmdbId) {
    if (!_ready) return null;
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
    revision.value++;
    onRemoved?.call(type, tmdbId);
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

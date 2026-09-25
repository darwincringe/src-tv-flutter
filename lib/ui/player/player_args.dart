/// Tracks whether the player route is currently on screen, so the app's
/// "return to what you were watching" logic doesn't push it twice.
class PlayerRuntime {
  static bool isOpen = false;

  /// Epoch-ms of the last time the user intentionally left the player. The
  /// auto-resume-on-resume logic ignores lifecycle events for a moment after
  /// this, so backing out of the player can't immediately re-open a new one.
  static int leftAt = 0;

  /// Epoch-ms until which a back event should be swallowed by the screen under
  /// a full-screen route (details). WSA sometimes delivers one physical back as
  /// two events (a key event + a system pop); after the trailer pops itself the
  /// stray second back would otherwise pop the details page too. Set on trailer
  /// exit; the details screen ignores a back that arrives before this time.
  static int backGuardUntil = 0;
}

enum PlayerMode { stream, trailer }

/// Arguments passed to the player route via `GoRouter` `extra`.
class PlayerArgs {
  final PlayerMode mode;
  final int? tmdbId;
  final String? type; // 'movie' | 'tv'
  final int? season;
  final int? episode;
  final String? trailerKey;
  /// Backdrop already known by the launching screen — shown on the loading
  /// screen immediately (at 0%), so no extra TMDB call is needed to display it.
  final String? backdropPath;

  const PlayerArgs.stream({
    required this.tmdbId,
    required this.type,
    this.season,
    this.episode,
    this.backdropPath,
  })  : mode = PlayerMode.stream,
        trailerKey = null;

  const PlayerArgs.trailer(this.trailerKey)
      : mode = PlayerMode.trailer,
        tmdbId = null,
        type = null,
        season = null,
        episode = null,
        backdropPath = null;
}

/// Tracks whether the player route is currently on screen, so the app's
/// "return to what you were watching" logic doesn't push it twice.
class PlayerRuntime {
  static bool isOpen = false;
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

  const PlayerArgs.stream({
    required this.tmdbId,
    required this.type,
    this.season,
    this.episode,
  })  : mode = PlayerMode.stream,
        trailerKey = null;

  const PlayerArgs.trailer(this.trailerKey)
      : mode = PlayerMode.trailer,
        tmdbId = null,
        type = null,
        season = null,
        episode = null;
}

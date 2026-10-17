import 'package:flutter/material.dart';

import '../../data/store/watch_progress.dart';

/// Orange box with a white check. Marks a movie or episode as watched.
class WatchedCheck extends StatelessWidget {
  const WatchedCheck({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFF9800),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Icon(
          Icons.check,
          color: Colors.white,
          size: size * 0.78,
        ),
      ),
    );
  }
}

/// The check for a movie that has reached 95% at least once.
class MovieWatchedBadge extends StatefulWidget {
  const MovieWatchedBadge({
    super.key,
    required this.tmdbId,
    this.size = 22,
    this.margin = EdgeInsets.zero,
  });

  final int tmdbId;
  final double size;
  final EdgeInsetsGeometry margin;

  @override
  State<MovieWatchedBadge> createState() => _MovieWatchedBadgeState();
}

class _MovieWatchedBadgeState extends State<MovieWatchedBadge> {
  @override
  void initState() {
    super.initState();
    WatchProgressStore.revision.addListener(_onProgress);
  }

  @override
  void dispose() {
    WatchProgressStore.revision.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final progress = WatchProgressStore.get('movie', widget.tmdbId);
    if (progress == null || !progress.isMovieWatched) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: widget.margin,
      child: WatchedCheck(size: widget.size),
    );
  }
}

/// The check for one episode that has reached 95% at least once.
class EpisodeWatchedBadge extends StatefulWidget {
  const EpisodeWatchedBadge({
    super.key,
    required this.tmdbId,
    required this.season,
    required this.episode,
    this.size = 22,
    this.margin = EdgeInsets.zero,
  });

  final int tmdbId;
  final int season;
  final int episode;
  final double size;
  final EdgeInsetsGeometry margin;

  @override
  State<EpisodeWatchedBadge> createState() => _EpisodeWatchedBadgeState();
}

class _EpisodeWatchedBadgeState extends State<EpisodeWatchedBadge> {
  @override
  void initState() {
    super.initState();
    WatchProgressStore.revision.addListener(_onProgress);
  }

  @override
  void dispose() {
    WatchProgressStore.revision.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final progress = WatchProgressStore.get('tv', widget.tmdbId);
    if (progress == null ||
        !progress.isEpisodeWatched(widget.season, widget.episode)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: widget.margin,
      child: WatchedCheck(size: widget.size),
    );
  }
}

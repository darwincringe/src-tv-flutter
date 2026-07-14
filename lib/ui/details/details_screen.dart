import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/focus.dart';
import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../data/models/credits.dart';
import '../../data/models/details_dto.dart';
import '../../data/models/media_details.dart';
import '../../data/models/media_item.dart';
import '../../data/repository/media_repository.dart';
import '../../data/store/watch_progress.dart';
import '../../data/tmdb/image_urls.dart';
import '../widgets/state_views.dart';

class DetailsScreen extends ConsumerStatefulWidget {
  const DetailsScreen({super.key, required this.mediaType, required this.id});
  final String mediaType;
  final int id;

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen>
    with WidgetsBindingObserver {
  MediaDetails? _details;
  List<MediaItem> _similar = [];
  Object? _error;

  int _selectedSeason = 1;
  List<Episode> _episodes = [];
  bool _episodesLoading = false;

  WatchProgress? _progress;

  final ScrollController _scroll = ScrollController();
  final GlobalKey _episodesKey = GlobalKey();
  final FocusNode _playFocus = FocusNode();
  final FocusNode _firstEpisodeFocus = FocusNode();

  String get _progressType => widget.mediaType == 'tv' ? 'tv' : 'movie';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _playFocus.dispose();
    _firstEpisodeFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {
        _progress = WatchProgressStore.get(_progressType, widget.id);
      });
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final repo = ref.read(mediaRepositoryProvider);
      final d = await repo.details(widget.mediaType, widget.id);
      final sim = (await repo.similar(widget.mediaType, widget.id)).take(12).toList();
      if (!mounted) return;
      setState(() {
        _details = d;
        _similar = sim;
        _progress = WatchProgressStore.get(_progressType, widget.id);
        if (d.isTv && d.seasons.isNotEmpty) {
          _selectedSeason = d.seasons.first.seasonNumber;
        }
      });
      if (d.isTv && d.seasons.isNotEmpty) _loadEpisodes(_selectedSeason);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _loadEpisodes(int season) async {
    setState(() {
      _episodesLoading = true;
      _episodes = [];
    });
    try {
      final eps = await ref.read(mediaRepositoryProvider).episodes(widget.id, season);
      if (!mounted) return;
      setState(() {
        _episodes = eps;
        _episodesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _episodesLoading = false);
    }
  }

  bool get _resumable => _progress?.isContinuable == true;

  void _onPlay() {
    final d = _details!;
    if (!d.isTv) {
      playStream(context, tmdbId: d.id, type: 'movie');
      return;
    }
    final saved = _progress;
    if (_resumable && saved?.episode != null) {
      playStream(
        context,
        tmdbId: d.id,
        type: 'tv',
        season: saved!.season,
        episode: saved.episode,
      );
      return;
    }
    // Fresh series: scroll to the episode list and focus the first episode.
    final ctx = _episodesKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
    }
    _firstEpisodeFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.charcoal,
        body: ErrorView(message: 'Failed to load.', onRetry: _load),
      );
    }
    final d = _details;
    if (d == null) {
      return const Scaffold(
        backgroundColor: AppColors.charcoal,
        body: LoadingView(),
      );
    }

    final portrait = MediaQuery.of(context).orientation == Orientation.portrait;

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      body: Stack(
        children: [
          Positioned.fill(child: _DetailsBackdrop(path: d.backdropPath)),
          SafeArea(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                _header(d, portrait),
                if (d.cast.isNotEmpty) _castSection(d),
                if (d.isTv && d.seasons.isNotEmpty) _seasonsSection(d),
                if (_similar.isNotEmpty) _moreLikeThis(portrait),
              ],
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              child: BackButton(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(MediaDetails d, bool portrait) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 48, 40, 8),
      child: FractionallySizedBox(
        widthFactor: portrait ? 1 : 0.52,
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              d.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (d.tagline != null) ...[
              const SizedBox(height: 6),
              Text(
                d.tagline!,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                _PlayButton(
                  label: _resumable ? 'Resume' : 'Play',
                  icon: Icons.play_arrow,
                  focusNode: _playFocus,
                  autofocus: true,
                  onTap: _onPlay,
                ),
                const SizedBox(width: 12),
                _PlayButton(
                  label: 'Watch Trailer',
                  icon: Icons.movie_outlined,
                  filled: false,
                  onTap: () {
                    final key = d.trailerKey;
                    if (key != null) {
                      playTrailer(context, key);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No trailer available')),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _metaRow(d),
            if (d.genres.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                d.genres.join('  ·  '),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              d.overview,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaRow(MediaDetails d) {
    final parts = <String>[];
    if (d.year != null) parts.add(d.year!);
    parts.add('★ ${d.rating.toStringAsFixed(1)}');
    if (d.runtimeMinutes != null && d.runtimeMinutes! > 0) {
      parts.add(_fmtRuntime(d.runtimeMinutes!));
    }
    if (d.isTv && d.numberOfSeasons > 0) {
      parts.add('${d.numberOfSeasons} Season${d.numberOfSeasons == 1 ? '' : 's'}');
    }
    if (d.language != null) parts.add(d.language!);
    return Text(
      parts.join('   •   '),
      style: const TextStyle(color: AppColors.textSecondary),
    );
  }

  String _fmtRuntime(int m) => m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';

  // ---- Cast --------------------------------------------------------------

  Widget _castSection(MediaDetails d) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 40, bottom: 10),
            child: Text(
              'Cast & Crew',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 40),
              itemCount: d.cast.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, i) => _CastCard(member: d.cast[i]),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Seasons + episodes ------------------------------------------------

  Widget _seasonsSection(MediaDetails d) {
    return Padding(
      key: _episodesKey,
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 40, bottom: 10),
            child: Text(
              'Seasons',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 40),
              itemCount: d.seasons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final s = d.seasons[i];
                final selected = s.seasonNumber == _selectedSeason;
                return _SeasonPill(
                  label: s.name ?? 'Season ${s.seasonNumber}',
                  selected: selected,
                  onTap: () {
                    setState(() => _selectedSeason = s.seasonNumber);
                    _loadEpisodes(s.seasonNumber);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (_episodesLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Loading episodes…',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            ...List.generate(_episodes.length, (i) {
              final e = _episodes[i];
              return _EpisodeRow(
                episode: e,
                focusNode: i == 0 ? _firstEpisodeFocus : null,
                onTap: () => playStream(
                  context,
                  tmdbId: d.id,
                  type: 'tv',
                  season: _selectedSeason,
                  episode: e.episodeNumber,
                ),
              );
            }),
        ],
      ),
    );
  }

  // ---- More like this ----------------------------------------------------

  Widget _moreLikeThis(bool portrait) {
    final columns = portrait ? 2 : 3;
    final rows = <Widget>[];
    for (var i = 0; i < _similar.length; i += columns) {
      final chunk = _similar.skip(i).take(columns).toList();
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) const SizedBox(width: 16),
              Expanded(
                child: c < chunk.length
                    ? _SimilarCard(
                        item: chunk[c],
                        onTap: () => openDetails(
                          context,
                          chunk[c].resolvedType(widget.mediaType),
                          chunk[c].id,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'More like this',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}

// ---- Small widgets -------------------------------------------------------

class _DetailsBackdrop extends StatelessWidget {
  const _DetailsBackdrop({required this.path});
  final String? path;

  @override
  Widget build(BuildContext context) {
    final url = backdropUrl(path);
    return LayoutBuilder(
      builder: (context, c) => Stack(
        children: [
          if (url != null)
            Positioned(
              top: 0,
              right: 0,
              width: c.maxWidth * 0.80,
              height: c.maxHeight * 0.75,
              child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
            ),
          // Horizontal fade: charcoal on the left → transparent, so the
          // image's left edge dissolves behind the title/overview.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [AppColors.charcoal, Color(0x00161616)],
                  stops: [0.32, 0.66],
                ),
              ),
            ),
          ),
          // Vertical fade: transparent → charcoal so the bottom edge dissolves
          // into the cast / more-like-this sections.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00161616), AppColors.charcoal],
                  stops: [0.42, 0.75],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = true,
    this.autofocus = false,
    this.focusNode,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onTap: onTap,
      autofocus: autofocus,
      focusNode: focusNode,
      focusedScale: 1.05,
      showBorder: false,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: filled ? AppColors.textPrimary : AppColors.charcoalLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: filled ? AppColors.charcoal : AppColors.textPrimary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: filled ? AppColors.charcoal : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CastCard extends StatelessWidget {
  const _CastCard({required this.member});
  final CastMember member;

  @override
  Widget build(BuildContext context) {
    final url = profileUrl(member.profilePath);
    final name = member.name ?? '';
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          ClipOval(
            child: SizedBox(
              width: 84,
              height: 84,
              child: url != null
                  ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                  : Container(
                      color: AppColors.charcoalLight,
                      alignment: Alignment.center,
                      child: Text(
                        name.isNotEmpty ? name[0] : '?',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 28,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            member.character ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeasonPill extends StatelessWidget {
  const _SeasonPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onTap: onTap,
      focusedScale: 1.05,
      showBorder: false,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : AppColors.charcoalLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.charcoal : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episode, required this.onTap, this.focusNode});
  final Episode episode;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final still = stillUrl(episode.stillPath);
    final meta = <String>[];
    if (episode.runtime != null) meta.add('${episode.runtime}m');
    if (episode.airDate != null) meta.add(episode.airDate!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 12),
      child: FocusableCard(
        onTap: onTap,
        focusNode: focusNode,
        focusedScale: 1.02,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          color: AppColors.charcoalLight,
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 150,
                  height: 84,
                  child: still != null
                      ? CachedNetworkImage(imageUrl: still, fit: BoxFit.cover)
                      : Container(color: AppColors.charcoal),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'E${episode.episodeNumber}  ·  ${episode.name ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (meta.isNotEmpty)
                      Text(
                        meta.join('  ·  '),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      episode.overview ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimilarCard extends StatelessWidget {
  const _SimilarCard({required this.item, required this.onTap});
  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = cardBackdropUrl(item.backdropPath);
    final date = item.releaseDate ?? item.firstAirDate ?? '';
    return FocusableCard(
      onTap: onTap,
      focusedScale: 1.04,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: AppColors.charcoalLight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: url != null
                  ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                  : Container(color: AppColors.charcoal),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '★ ${(item.voteAverage ?? 0).toStringAsFixed(1)}   $date',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.overview ?? '',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

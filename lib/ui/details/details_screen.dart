import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/focus.dart';
import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../data/models/credits.dart';
import '../../data/models/details_dto.dart';
import '../../data/models/media_details.dart';
import '../../data/models/media_item.dart';
import '../../data/repository/media_repository.dart';
import '../../data/store/library_store.dart';
import '../../data/store/watch_progress.dart';
import '../../data/tmdb/image_urls.dart';
import '../player/player_args.dart';
import '../widgets/coming_soon_badge.dart';
import '../widgets/episode_window.dart';
import '../widgets/sliding_window.dart';
import '../widgets/state_views.dart';
import '../widgets/watched_check.dart';

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
  List<String> _gallery = [];
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
    // Refresh the resume point whenever playback progress changes — this fires
    // when returning from the player (in-app nav, not an app resume), so the
    // button flips to "Resume" with the new timestamp instead of staying "Play".
    WatchProgressStore.revision.addListener(_refreshProgress);
    // Keep the "Add to Library" toggle in sync if it changes elsewhere.
    LibraryStore.revision.addListener(_onLibraryChange);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WatchProgressStore.revision.removeListener(_refreshProgress);
    LibraryStore.revision.removeListener(_onLibraryChange);
    _scroll.dispose();
    _playFocus.dispose();
    _firstEpisodeFocus.dispose();
    super.dispose();
  }

  void _refreshProgress() {
    if (!mounted) return;
    setState(() {
      _progress = WatchProgressStore.get(_progressType, widget.id);
    });
  }

  void _onLibraryChange() {
    if (mounted) setState(() {});
  }

  void _toggleLibrary() {
    final d = _details;
    if (d == null) return;
    LibraryStore.toggle(LibraryItem(
      tmdbId: widget.id,
      type: _progressType,
      title: d.title,
      posterPath: d.posterPath,
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshProgress();
  }

  @override
  void didUpdateWidget(DetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.mediaType != widget.mediaType) {
      _details = null;
      _similar = [];
      _gallery = [];
      _episodes = [];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final repo = ref.read(mediaRepositoryProvider);
      final d = await repo.details(widget.mediaType, widget.id);
      final sim = await repo.similar(widget.mediaType, widget.id);
      List<String> gallery = const [];
      try {
        gallery = await repo.gallery(widget.mediaType, widget.id);
      } catch (_) {
        gallery = const [];
      }
      if (!mounted) return;
      setState(() {
        _details = d;
        _similar = sim;
        _gallery = gallery;
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
      playStream(
        context,
        tmdbId: d.id,
        type: 'movie',
        backdropPath: d.backdropPath,
        posterPath: d.posterPath,
      );
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
        backdropPath: d.backdropPath,
        posterPath: d.posterPath,
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
    // Intercept back so a stray second back event right after a trailer exits
    // (WSA can double-deliver one press) doesn't pop this screen too.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now < PlayerRuntime.backGuardUntil) {
          PlayerRuntime.backGuardUntil = 0; // consume the guard once
          return; // swallow the stray back from the trailer exit
        }
        backFromDetails(context);
      },
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
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
                if (_gallery.isNotEmpty) _gallerySection(),
                if (_similar.isNotEmpty) _moreLikeThis(portrait),
              ],
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              child: _FocusBackButton(onTap: () => backFromDetails(context)),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    d.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!d.isTv)
                  MovieWatchedBadge(
                    tmdbId: d.id,
                    size: 28,
                    margin: const EdgeInsets.only(left: 10),
                  ),
              ],
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
            if (d.comingSoon) ...[
              const SizedBox(height: 12),
              const Row(children: [ComingSoonBadge(big: true)]),
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
                const SizedBox(width: 12),
                Builder(builder: (context) {
                  final inLib = LibraryStore.contains(_progressType, widget.id);
                  return _PlayButton(
                    label: inLib ? 'In Library' : 'Add to Library',
                    icon: inLib ? Icons.check : Icons.add,
                    filled: false,
                    onTap: _toggleLibrary,
                  );
                }),
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
    // Where the user left off (resume point), beside the language.
    if (d.isTv && _resumable && _progress?.episode != null) {
      parts.add('S${_progress!.season ?? 1} E${_progress!.episode}');
    }
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
                return Center(
                  child: _SeasonPill(
                    label: s.name ?? 'Season ${s.seasonNumber}',
                    selected: s.seasonNumber == _selectedSeason,
                    onTap: () {
                      setState(() => _selectedSeason = s.seasonNumber);
                      _loadEpisodes(s.seasonNumber);
                    },
                  ),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: EpisodeWindow(
                key: ValueKey(_selectedSeason),
                itemCount: _episodes.length,
                firstItemFocusNode: _firstEpisodeFocus,
                itemBuilder: (context, i, lead, focusNode) {
                  final ep = _episodes[i];
                  return _EpisodeRow(
                    tmdbId: d.id,
                    season: _selectedSeason,
                    episode: ep,
                    flush: true,
                    focusNode: focusNode,
                    onTap: () => playStream(
                      context,
                      tmdbId: d.id,
                      type: 'tv',
                      season: _selectedSeason,
                      episode: ep.episodeNumber,
                      backdropPath: d.backdropPath,
        posterPath: d.posterPath,
                    ),
                  );
                },
                seeMoreBuilder: (context, i, focusNode, onTap) => _EpisodeSeeMore(
                  episode: _episodes[i],
                  focusNode: focusNode,
                  onTap: onTap,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- Gallery -----------------------------------------------------------

  Widget _gallerySection() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 40, bottom: 10),
            child: Text(
              'Gallery',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
              itemCount: _gallery.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _GalleryCard(path: _gallery[i]),
            ),
          ),
        ],
      ),
    );
  }

  // ---- More like this ----------------------------------------------------

  Widget _moreLikeThis(bool portrait) {
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
          SlidingWindow(
            itemCount: _similar.length,
            columns: portrait ? 2 : 3,
            rows: 2,
            initialTitles: 5,
            titleLimit: 10,
            step: 5,
            gap: 16,
            cardAspect: 16 / 9,
            extraHeight: 120,
            imageUrl: (i) => cardBackdropUrl(_similar[i].backdropPath),
            itemBuilder: (context, i, lead, focusNode) {
              final item = _similar[i];
              return _SimilarCard(
                item: item,
                focusNode: focusNode,
                onTap: () => openDetails(
                  context,
                  item.resolvedType(widget.mediaType),
                  item.id,
                ),
              );
            },
          ),
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
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth:
                    (c.maxWidth * 0.80 * MediaQuery.devicePixelRatioOf(context))
                        .round()
                        .clamp(320, 1280),
              ),
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

/// Back button with a clear D-pad focus ring (the Material default is too faint
/// for a TV across the room).
class _FocusBackButton extends StatefulWidget {
  const _FocusBackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_FocusBackButton> createState() => _FocusBackButtonState();
}

class _FocusBackButtonState extends State<_FocusBackButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onFocusChange: (f) => setState(() => _focused = f),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                _focused ? AppColors.focusRing : Colors.black.withValues(alpha: 0.35),
          ),
          child: Icon(
            Icons.arrow_back,
            color: _focused ? Colors.black : AppColors.textPrimary,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatefulWidget {
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
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onTap: widget.onTap,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      focusedScale: 1.05,
      showBorder: false,
      onFocusChange: (f) => setState(() => _focused = f),
      // Keep the title/header in view when the Play row is focused.
      ensureVisibleOnFocus: true,
      ensureVisibleAlignment: 0.55,
      borderRadius: BorderRadius.circular(11),
      child: FocusRing(
        focused: _focused,
        radius: 11,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: widget.filled ? AppColors.textPrimary : AppColors.charcoalLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 20,
                color: widget.filled ? AppColors.charcoal : AppColors.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.filled ? AppColors.charcoal : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
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
                  ? CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      memCacheWidth:
                          (84 * MediaQuery.devicePixelRatioOf(context)).round(),
                    )
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

class _SeasonPill extends StatefulWidget {
  const _SeasonPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SeasonPill> createState() => _SeasonPillState();
}

class _SeasonPillState extends State<_SeasonPill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onTap: widget.onTap,
      focusedScale: 1.05,
      showBorder: false,
      onFocusChange: (f) => setState(() => _focused = f),
      ensureVisibleOnFocus: true,
      borderRadius: BorderRadius.circular(23),
      child: FocusRing(
        focused: _focused,
        radius: 23,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected ? AppColors.textPrimary : AppColors.charcoalLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.selected ? AppColors.charcoal : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.tmdbId,
    required this.season,
    required this.episode,
    required this.onTap,
    this.focusNode,
    this.flush = false,
  });
  final int tmdbId;
  final int season;
  final Episode episode;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool flush;

  @override
  Widget build(BuildContext context) {
    final still = stillUrl(episode.stillPath);
    final comingSoon = isComingSoon(episode.airDate);
    final meta = <String>[];
    if (episode.runtime != null) meta.add('${episode.runtime}m');
    if (episode.airDate != null && episode.airDate!.isNotEmpty) {
      meta.add(formatDate(episode.airDate));
    }
    return Padding(
      padding: flush ? EdgeInsets.zero : const EdgeInsets.fromLTRB(40, 0, 40, 12),
      child: FocusableCard(
        onTap: onTap,
        focusNode: focusNode,
        focusedScale: 1.02,
        ensureVisibleOnFocus: true,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 150,
                height: 84,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: still != null
                          ? CachedNetworkImage(
                              imageUrl: still,
                              fit: BoxFit.cover,
                              memCacheWidth: (150 *
                                      MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                            )
                          : Container(color: AppColors.charcoal),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: EpisodeWatchedBadge(
                        tmdbId: tmdbId,
                        season: season,
                        episode: episode.episodeNumber,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'E${episode.episodeNumber}  ·  ${episode.name ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        EpisodeWatchedBadge(
                          tmdbId: tmdbId,
                          season: season,
                          episode: episode.episodeNumber,
                          margin: const EdgeInsets.only(left: 8),
                        ),
                        if (comingSoon) ...[
                          const SizedBox(width: 8),
                          const ComingSoonBadge(),
                        ],
                      ],
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

/// Same shape as an episode row: the next still, a "See more" title, and no
/// description. The picture is blurred so it is not another episode to play.
class _EpisodeSeeMore extends StatelessWidget {
  const _EpisodeSeeMore({
    required this.episode,
    required this.onTap,
    required this.focusNode,
  });

  final Episode episode;
  final VoidCallback onTap;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final still = stillUrl(episode.stillPath);
    return FocusableCard(
      onTap: onTap,
      focusNode: focusNode,
      focusedScale: 1.02,
      ensureVisibleOnFocus: true,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 150,
                height: 84,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (still != null)
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Transform.scale(
                          scale: 1.15,
                          child: CachedNetworkImage(
                            imageUrl: still,
                            fit: BoxFit.cover,
                            width: 150,
                            height: 84,
                            memCacheWidth: (150 *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round(),
                          ),
                        ),
                      )
                    else
                      const ColoredBox(color: AppColors.charcoal),
                    const ColoredBox(color: Color(0x99000000)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'See more',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryCard extends StatelessWidget {
  const _GalleryCard({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final url = posterUrl(path);
    return FocusableCard(
      focusedScale: 1.04,
      ensureVisibleOnFocus: true,
      borderRadius: BorderRadius.circular(6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 120,
          height: 180,
          child: url != null
              ? CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  memCacheWidth:
                      (120 * MediaQuery.devicePixelRatioOf(context)).round(),
                )
              : Container(color: AppColors.charcoalLight),
        ),
      ),
    );
  }
}

class _SimilarCard extends StatelessWidget {
  const _SimilarCard({
    required this.item,
    required this.onTap,
    this.focusNode,
  });
  final MediaItem item;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final url = cardBackdropUrl(item.backdropPath);
    final year = item.year ?? '';
    return FocusableCard(
      onTap: onTap,
      focusNode: focusNode,
      focusedScale: 1.04,
      ensureVisibleOnFocus: true,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: AppColors.charcoalLight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: url != null
                  ? LayoutBuilder(
                      builder: (ctx, c) => CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        memCacheWidth:
                            (c.maxWidth * MediaQuery.devicePixelRatioOf(ctx))
                                .round()
                                .clamp(160, 780),
                      ),
                    )
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
                    year.isEmpty
                        ? '★ ${(item.voteAverage ?? 0).toStringAsFixed(1)}'
                        : '★ ${(item.voteAverage ?? 0).toStringAsFixed(1)}   $year',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.overview ?? '',
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
    );
  }
}

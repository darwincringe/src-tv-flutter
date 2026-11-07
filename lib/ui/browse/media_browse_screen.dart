import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation.dart';
import '../../data/models/media_details.dart';
import '../../data/models/media_item.dart';
import '../../data/repository/media_repository.dart';
import '../../data/store/recommendation_seeds.dart';
import '../../data/store/watch_progress.dart';
import '../widgets/branded_loader.dart';
import '../widgets/category_row.dart';
import '../widgets/continue_watching_row.dart';
import '../widgets/hero_backdrop.dart';
import '../widgets/state_views.dart';

/// Shared hero-plus-rows screen used by Home, Movies and Series. Renders once
/// as a stable structure after personalized rows load (so initial focus lands
/// and holds), and refreshes personalization on app resume. Mirrors the Kotlin
/// `MediaBrowseScreen` + `BrowseViewModel`.
class MediaBrowseScreen extends ConsumerStatefulWidget {
  const MediaBrowseScreen({
    super.key,
    required this.scope, // 'home' | 'movie' | 'tv'
    required this.loadRows,
    this.showContinueWatching = false,
  });

  final String scope;
  final List<CategorySource> Function(MediaRepository repo) loadRows;
  final bool showContinueWatching;

  @override
  ConsumerState<MediaBrowseScreen> createState() => _MediaBrowseScreenState();
}

class _MediaBrowseScreenState extends ConsumerState<MediaBrowseScreen>
    with WidgetsBindingObserver {
  List<CategorySource>? _sources;
  List<WatchProgress> _continueWatching = [];
  bool _personalizedReady = false;
  bool _recommendedEmpty = false;
  Object? _error;
  MediaItem? _hero;
  // Rich details for the focused hero (year/rating/runtime/language/genres),
  // fetched lazily so the top hero shows the same info as the details page.
  MediaDetails? _heroDetails;
  int? _heroSeason; // set when a Continue-Watching (TV) item is focused
  int? _heroEpisode;
  Timer? _heroDebounce;
  int _heroReqId = 0;
  int _personalGen = 0;

  final FocusNode _firstCardFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Refresh Continue Watching whenever playback progress changes — this fires
    // on returning from the player (in-app navigation, which is NOT an app
    // resume) so the row updates immediately after watching something.
    WatchProgressStore.revision.addListener(_onAccountData);
  }

  bool _activated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The shell keeps every tab alive. Only the visible one should talk to
    // TMDB, otherwise Home also pays for Movies and Series.
    if (_activated || !TickerMode.valuesOf(context).enabled) return;
    _activated = true;
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WatchProgressStore.revision.removeListener(_onAccountData);
    _heroDebounce?.cancel();
    _firstCardFocus.dispose();
    super.dispose();
  }

  void _onAccountData() {
    if (mounted && _activated && _sources != null) _loadPersonalized();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _activated && _sources != null) {
      _loadPersonalized();
    }
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
    });
    try {
      final repo = ref.read(mediaRepositoryProvider);
      final sources = widget.loadRows(repo);
      final cw = widget.showContinueWatching
          ? await repo.continueWatching()
          : <WatchProgress>[];
      if (!mounted) return;
      setState(() {
        _sources = sources;
        _continueWatching = cw;
        _personalizedReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _loadPersonalized() async {
    final gen = ++_personalGen;
    try {
      final repo = ref.read(mediaRepositoryProvider);
      final cw = widget.showContinueWatching
          ? await repo.continueWatching()
          : <WatchProgress>[];
      if (!mounted || gen != _personalGen) return;
      setState(() {
        _continueWatching = cw;
        _personalizedReady = true;
      });
    } catch (_) {
      if (!mounted || gen != _personalGen) return;
      setState(() => _personalizedReady = true);
    }
  }

  /// Sets the hero to [item] immediately, then (debounced, so fast scrolling
  /// doesn't spam the API) fetches its details to enrich the hero metadata.
  void _focusHeroItem(MediaItem item, String fallbackType) {
    final reqId = ++_heroReqId;
    setState(() {
      _hero = item;
      _heroDetails = null;
      _heroSeason = null; // row items aren't "continuing" a specific episode
      _heroEpisode = null;
    });
    _heroDebounce?.cancel();
    _heroDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final type = item.resolvedType(fallbackType);
        final d = await ref.read(mediaRepositoryProvider).details(
              type,
              item.id,
              extras: false,
            );
        if (mounted && reqId == _heroReqId) setState(() => _heroDetails = d);
      } catch (_) {}
    });
  }

  void _onProgressFocused(WatchProgress p) async {
    final reqId = ++_heroReqId;
    _heroDebounce?.cancel();
    try {
      final d = await ref
          .read(mediaRepositoryProvider)
          .details(p.type, p.tmdbId, extras: false);
      if (!mounted || reqId != _heroReqId) return;
      setState(() {
        _hero = MediaItem(
          id: p.tmdbId,
          mediaType: p.type,
          title: d.isTv ? null : d.title,
          name: d.isTv ? d.title : null,
          overview: d.overview,
          backdropPath: d.backdropPath,
          posterPath: d.posterPath,
          voteAverage: d.rating,
        );
        _heroDetails = d;
        // Show which season/episode the user is on, in the hero meta line.
        _heroSeason = d.isTv ? (p.season ?? 1) : null;
        _heroEpisode = d.isTv ? (p.episode ?? 1) : null;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ErrorView(message: 'Something went wrong.', onRetry: _load);
    }
    if (_sources == null || !_personalizedReady) {
      // Home's first load is the app's cold-start — show the full branded
      // splash (logo + spinner + caption), handing off from the native splash.
      return widget.scope == 'home'
          ? const BrandedLoader(caption: 'Loading your library…')
          : const LoadingView();
    }

    final portrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    return LayoutBuilder(
      builder: (context, constraints) {
        final heroHeight = constraints.maxHeight * 0.42;
        return Stack(
          children: [
            // Isolated layer: the hero image + gradients don't repaint with the
            // card grid when focus moves between posters.
            Positioned.fill(
              child: RepaintBoundary(child: HeroBackdrop(item: _hero)),
            ),
            Column(
              children: [
                SizedBox(
                  height: heroHeight,
                  width: double.infinity,
                  child: HeroInfo(
                    item: _hero,
                    portrait: portrait,
                    details: _heroDetails,
                    season: _heroSeason,
                    episode: _heroEpisode,
                  ),
                ),
                Expanded(child: _buildRows()),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildRows() {
    final sections = <Widget>[];
    var focusAssigned = false;

    if (_continueWatching.isNotEmpty) {
      sections.add(ContinueWatchingRow(
        title: 'Continue Watching',
        items: _continueWatching,
        autofocusFirst: true,
        firstItemFocusNode: _firstCardFocus,
        onFocus: _onProgressFocused,
        onTap: (p) => openDetails(context, p.type, p.tmdbId),
      ));
      focusAssigned = true;
    }

    final fallback = widget.scope == 'tv' ? 'tv' : 'movie';
    sections.add(_LazyRecommended(
      key: ValueKey('recommended-${widget.scope}'),
      scope: widget.scope,
      autofocusFirst: !focusAssigned,
      firstItemFocusNode: focusAssigned ? null : _firstCardFocus,
      onEmpty: () {
        if (mounted && !_recommendedEmpty) {
          setState(() => _recommendedEmpty = true);
        }
      },
      onItems: _claimHero,
      onItemFocus: (item) => _focusHeroItem(item, fallback),
      onItemTap: (item) => openDetails(
        context,
        item.resolvedType(fallback),
        item.id,
      ),
    ));
    if (!_recommendedEmpty) focusAssigned = true;

    for (var i = 0; i < _sources!.length; i++) {
      final source = _sources![i];
      final assignFocus = !focusAssigned && i == 0;
      sections.add(LazyCategoryRow(
        key: ValueKey('${widget.scope}-${source.title}'),
        source: source,
        autofocusFirst: assignFocus,
        firstItemFocusNode: assignFocus ? _firstCardFocus : null,
        onItems: assignFocus ? _claimHero : null,
        onItemFocus: (item) => _focusHeroItem(item, source.fallbackType),
        onItemTap: (item) => openDetails(
          context,
          item.resolvedType(source.fallbackType),
          item.id,
        ),
      ));
      if (assignFocus) focusAssigned = true;
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => sections[index],
    );
  }

  void _claimHero(List<MediaItem> items) {
    if (_hero != null || items.isEmpty || !mounted) return;
    setState(() => _hero = items.first);
  }
}

/// Recommendations load when this row is on screen, not with the rest of the page.
class _LazyRecommended extends ConsumerStatefulWidget {
  const _LazyRecommended({
    super.key,
    required this.scope,
    required this.onItemTap,
    required this.onItemFocus,
    required this.onEmpty,
    this.onItems,
    this.firstItemFocusNode,
    this.autofocusFirst = false,
  });

  final String scope;
  final void Function(MediaItem item) onItemTap;
  final void Function(MediaItem item) onItemFocus;
  final VoidCallback onEmpty;
  final void Function(List<MediaItem> items)? onItems;
  final FocusNode? firstItemFocusNode;
  final bool autofocusFirst;

  @override
  ConsumerState<_LazyRecommended> createState() => _LazyRecommendedState();
}

class _LazyRecommendedState extends ConsumerState<_LazyRecommended> {
  List<MediaItem>? _items;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    RecommendationSeeds.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    RecommendationSeeds.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final gen = ++_gen;
    try {
      final items =
          await ref.read(mediaRepositoryProvider).recommended(widget.scope);
      if (!mounted || gen != _gen) return;
      setState(() => _items = items);
      if (items.isEmpty) {
        widget.onEmpty();
      } else {
        widget.onItems?.call(items);
      }
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() => _items = const []);
      widget.onEmpty();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final fallback = widget.scope == 'tv' ? 'tv' : 'movie';
    return CategoryRowSection(
      row: CategoryRow(
        title: 'Recommended for you',
        fallbackType: fallback,
        items: items,
      ),
      autofocusFirst: widget.autofocusFirst,
      firstItemFocusNode: widget.firstItemFocusNode,
      onItemFocus: widget.onItemFocus,
      onItemTap: widget.onItemTap,
    );
  }
}

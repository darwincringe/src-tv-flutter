import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation.dart';
import '../../data/models/media_details.dart';
import '../../data/models/media_item.dart';
import '../../data/repository/media_repository.dart';
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
  final Future<List<CategoryRow>> Function(MediaRepository repo) loadRows;
  final bool showContinueWatching;

  @override
  ConsumerState<MediaBrowseScreen> createState() => _MediaBrowseScreenState();
}

class _MediaBrowseScreenState extends ConsumerState<MediaBrowseScreen>
    with WidgetsBindingObserver {
  List<CategoryRow>? _rows;
  List<MediaItem> _recommended = [];
  List<WatchProgress> _continueWatching = [];
  bool _personalizedReady = false;
  Object? _error;
  MediaItem? _hero;
  // Rich details for the focused hero (year/rating/runtime/language/genres),
  // fetched lazily so the top hero shows the same info as the details page.
  MediaDetails? _heroDetails;
  Timer? _heroDebounce;
  int _heroReqId = 0;

  final FocusNode _firstCardFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Refresh Continue Watching whenever playback progress changes — this fires
    // on returning from the player (in-app navigation, which is NOT an app
    // resume) so the row updates immediately after watching something.
    WatchProgressStore.revision.addListener(_onProgressChanged);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WatchProgressStore.revision.removeListener(_onProgressChanged);
    _heroDebounce?.cancel();
    _firstCardFocus.dispose();
    super.dispose();
  }

  void _onProgressChanged() {
    if (mounted && _rows != null && widget.showContinueWatching) {
      _loadPersonalized();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _rows != null) {
      _loadPersonalized();
    }
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
    });
    try {
      final repo = ref.read(mediaRepositoryProvider);
      final rows = await widget.loadRows(repo);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _hero ??= rows.isNotEmpty && rows.first.items.isNotEmpty
            ? rows.first.items.first
            : null;
      });
      await _loadPersonalized();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _loadPersonalized() async {
    try {
      final repo = ref.read(mediaRepositoryProvider);
      final rec = await repo.recommended(widget.scope);
      final cw = widget.showContinueWatching
          ? await repo.continueWatching()
          : <WatchProgress>[];
      if (!mounted) return;
      setState(() {
        _recommended = rec;
        _continueWatching = cw;
        _personalizedReady = true;
      });
    } catch (_) {
      if (!mounted) return;
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
    });
    _heroDebounce?.cancel();
    _heroDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final type = item.resolvedType(fallbackType);
        final d = await ref.read(mediaRepositoryProvider).details(type, item.id);
        if (mounted && reqId == _heroReqId) setState(() => _heroDetails = d);
      } catch (_) {}
    });
  }

  void _onProgressFocused(WatchProgress p) async {
    final reqId = ++_heroReqId;
    _heroDebounce?.cancel();
    try {
      final d = await ref.read(mediaRepositoryProvider).details(p.type, p.tmdbId);
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
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ErrorView(message: 'Something went wrong.', onRetry: _load);
    }
    if (_rows == null || !_personalizedReady) {
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

    if (_recommended.isNotEmpty) {
      sections.add(CategoryRowSection(
        row: CategoryRow(
          title: 'Recommended for you',
          fallbackType: widget.scope == 'tv' ? 'tv' : 'movie',
          items: _recommended,
        ),
        autofocusFirst: !focusAssigned,
        firstItemFocusNode: focusAssigned ? null : _firstCardFocus,
        onItemFocus: (item) =>
            _focusHeroItem(item, widget.scope == 'tv' ? 'tv' : 'movie'),
        onItemTap: (item) => openDetails(
          context,
          item.resolvedType(widget.scope == 'tv' ? 'tv' : 'movie'),
          item.id,
        ),
      ));
      focusAssigned = true;
    }

    for (var i = 0; i < _rows!.length; i++) {
      final row = _rows![i];
      final assignFocus = !focusAssigned && i == 0;
      sections.add(CategoryRowSection(
        row: row,
        autofocusFirst: assignFocus,
        firstItemFocusNode: assignFocus ? _firstCardFocus : null,
        onItemFocus: (item) => _focusHeroItem(item, row.fallbackType),
        onItemTap: (item) =>
            openDetails(context, item.resolvedType(row.fallbackType), item.id),
      ));
      if (assignFocus) focusAssigned = true;
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 18),
      itemBuilder: (context, index) => sections[index],
    );
  }
}

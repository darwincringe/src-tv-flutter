import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/focus.dart';
import '../../core/theme.dart';
import '../../data/repository/media_repository.dart';
import '../../data/store/watch_progress.dart';
import 'poster_card.dart';
import 'watched_check.dart';

/// Slides a fixed window of posters by [step]. Moving forward hides [step]
/// titles from the front and reveals [step] later ones. Moving back does the
/// opposite, so the grid never grows.
int posterWindowStart({
  required int start,
  required int total,
  required int window,
  required int step,
  required bool forward,
}) {
  if (window <= 0 || total <= 0) return 0;
  final maxStart = total <= window ? 0 : total - window;
  final current = start.clamp(0, maxStart);
  final next = forward ? current + step : current - step;
  return next.clamp(0, maxStart);
}

/// How many posters fit in [capacity] cells once See more cards take a slot
/// at each end that still has hidden titles.
class PosterWindow {
  const PosterWindow({
    required this.start,
    required this.shown,
    required this.canBack,
    required this.canForward,
  });

  final int start;
  final int shown;
  final bool canBack;
  final bool canForward;

  /// Title just before this window, used as the back card's poster.
  int get previousIndex => start - 1;

  /// First title after this window, used as the forward card's poster.
  int get nextIndex => start + shown;
}

PosterWindow posterWindow({
  required int start,
  required int total,
  required int capacity,
}) {
  if (capacity <= 0 || total <= 0) {
    return const PosterWindow(
      start: 0,
      shown: 0,
      canBack: false,
      canForward: false,
    );
  }
  if (total <= capacity) {
    return PosterWindow(
      start: 0,
      shown: total,
      canBack: false,
      canForward: false,
    );
  }
  final endWindow = math.max(1, capacity - 1);
  final maxStart = math.max(0, total - endWindow);
  final clamped = start.clamp(0, maxStart);
  final atStart = clamped == 0;
  final atEnd = clamped >= maxStart;
  var shown = capacity;
  if (!atStart) shown -= 1;
  if (!atEnd) shown -= 1;
  if (shown < 1) shown = 1;
  if (clamped + shown > total) shown = total - clamped;
  return PosterWindow(
    start: clamped,
    shown: shown,
    canBack: clamped > 0,
    canForward: clamped + shown < total,
  );
}

/// Slides [start] by [step], staying on a full page.
int nextPosterStart({
  required int start,
  required int total,
  required int capacity,
  required int step,
  required bool forward,
}) {
  final page = posterWindow(start: start, total: total, capacity: capacity);
  if (total <= capacity || capacity <= 0) return 0;
  final endWindow = math.max(1, capacity - 1);
  final maxStart = math.max(0, total - endWindow);
  final next = forward ? page.start + step : page.start - step;
  return next.clamp(0, maxStart);
}

/// A poster row that scrolls. See more appends the next [step] titles and
/// leaves the ones already on screen where they are.
class PagedPosterGrid extends StatefulWidget {
  const PagedPosterGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.posterPath,
    this.rows = 3,
    this.step = 5,
    this.firstItemFocusNode,
    this.onVisible,
  });

  final int itemCount;
  final Widget Function(
    BuildContext context,
    int index,
    bool lead,
    FocusNode? focusNode,
  ) itemBuilder;
  final String? Function(int index) posterPath;
  final int rows;
  final int step;
  final FocusNode? firstItemFocusNode;

  /// Called with the posters actually on screen, including after See more.
  final void Function(int start, int shown)? onVisible;

  @override
  State<PagedPosterGrid> createState() => _PagedPosterGridState();
}

class _Slot {
  const _Slot({required this.id, required this.rect, required this.child});

  final String id;
  final Rect rect;
  final Widget child;
}

class _PagedPosterGridState extends State<PagedPosterGrid> {
  static const double _extent = 132;
  static const double _gap = 14;
  static const double _rowGap = 16;

  bool _portrait = false;
  int? _portraitShown;
  final ScrollController _scroller = ScrollController();
  final FocusNode _beginFocus = FocusNode(debugLabel: 'see-more-begin');
  final FocusNode _endFocus = FocusNode(debugLabel: 'see-more-end');
  final FocusNode _leadFocus = FocusNode(debugLabel: 'paged-lead');
  final Map<int, FocusNode> _itemFocus = {};
  int? _visibleStart;
  int? _visibleShown;
  bool _visibleQueued = false;

  @override
  void dispose() {
    _scroller.dispose();
    _beginFocus.dispose();
    _endFocus.dispose();
    _leadFocus.dispose();
    for (final node in _itemFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _nodeFor(int index) => _itemFocus.putIfAbsent(
        index,
        () => FocusNode(debugLabel: 'poster-$index'),
      );

  FocusNode get _leadNode => widget.firstItemFocusNode ?? _leadFocus;

  void _move(int total, int capacity, bool forward) {
    if (forward) _growPortrait(total, capacity);
  }


  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width <= 0) return const SizedBox.shrink();
        _portrait = MediaQuery.orientationOf(context) == Orientation.portrait &&
            width < 700;
        return _portraitStrip(width, widget.itemCount);
      },
    );
  }

  /// Adds the next titles after the ones already on screen. Existing cards
  /// and the scroll position stay put, so the title in view does not move.
  void _growPortrait(int total, int capacity) {
    final shown = _portraitShown ?? _firstPortraitShown(total, capacity);
    if (shown >= total) return;
    final next = math.min(total, shown + widget.step);
    if (next == shown) return;
    // The See more card is the next title. Keep the remote on that title
    // once it becomes a real poster, instead of dropping back to the first.
    final revealed = shown;
    _nodeFor(revealed);
    setState(() => _portraitShown = next);
    _noteRange(0, next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _itemFocus[revealed];
      if (node != null && node.canRequestFocus) node.requestFocus();
    });
  }

  int _firstPortraitShown(int total, int capacity) {
    if (total <= capacity) return total;
    return math.max(1, capacity - 1);
  }

  void _noteRange(int start, int shown) {
    if (widget.onVisible == null || shown <= 0) return;
    if (_visibleStart == start && _visibleShown == shown) return;
    _visibleStart = start;
    _visibleShown = shown;
    if (_visibleQueued) return;
    _visibleQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleQueued = false;
      if (!mounted || _visibleStart == null || _visibleShown == null) return;
      widget.onVisible!(_visibleStart!, _visibleShown!);
    });
  }

  /// Portrait scrolls a fixed-size row. See more appends titles to the right.
  Widget _portraitStrip(double width, int total) {
    final viewportCols = math.max(1, (width / (_extent + _gap)).floor());
    final pageCols = math.max(10, viewportCols + 3);
    final capacity = pageCols * widget.rows;
    final shown = math.min(
      total,
      _portraitShown ?? _firstPortraitShown(total, capacity),
    );
    _portraitShown = shown;
    _noteRange(0, shown);
    if (shown <= 0) return const SizedBox.shrink();

    const cardWidth = _extent;
    final cardHeight = cardWidth * 3 / 2;
    // Room for the focus ring, which is drawn around the poster. Without it
    // the row clips the top and bottom of the selected card.
    const focusPad = 12.0;
    final rows = math.max(1, widget.rows);
    final page = PosterWindow(
      start: 0,
      shown: shown,
      canBack: false,
      canForward: shown < total,
    );
    final ids = <String>[
      for (var i = 0; i < shown; i++) 'p$i',
      if (page.canForward) 'forward',
    ];
    Rect at(int slot) {
      final col = slot ~/ rows;
      final row = slot % rows;
      return Rect.fromLTWH(
        focusPad + col * (cardWidth + _gap),
        focusPad + row * (cardHeight + _rowGap),
        cardWidth,
        cardHeight,
      );
    }

    final placed = [
      for (var i = 0; i < ids.length; i++)
        _Slot(
          id: ids[i],
          rect: at(i),
          child: _childForId(ids[i], page, total, capacity),
        ),
    ];
    final contentWidth =
        placed.map((slot) => slot.rect.right).reduce(math.max) + focusPad;
    final height =
        placed.map((slot) => slot.rect.bottom).reduce(math.max) + focusPad;
    return SizedBox(
      width: width,
      height: height,
      child: SingleChildScrollView(
        controller: _scroller,
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: math.max(width, contentWidth),
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final slot in placed)
                Positioned.fromRect(
                  key: ValueKey(slot.id),
                  rect: slot.rect,
                  child: slot.child,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _childForId(String id, PosterWindow page, int total, int capacity) {
    if (id == 'back') {
      return _seeMore(page.previousIndex, total, capacity, back: true);
    }
    if (id == 'forward') {
      return _seeMore(page.nextIndex, total, capacity, back: false);
    }
    final index = int.parse(id.substring(1));
    final lead = index == 0 && page.start == 0;
    final node = _itemFocus[index] ?? (lead ? _leadNode : null);
    return widget.itemBuilder(context, index, lead, node);
  }

  Widget _seeMore(int index, int total, int capacity, {required bool back}) {
    final path = index >= 0 && index < total ? widget.posterPath(index) : null;
    return SeeMorePoster(
      posterPath: path,
      focusNode: back ? _beginFocus : _endFocus,
      ensureVisible: !_portrait,
      onTap: () => _move(total, capacity, !back),
    );
  }
}

/// Poster-sized See more: the next (or previous) title, blurred and darkened,
/// with white "See more" in the middle.
class SeeMorePoster extends StatelessWidget {
  const SeeMorePoster({
    super.key,
    required this.onTap,
    required this.focusNode,
    this.posterPath,
    this.imageUrl,
    this.ensureVisible = true,
  });

  final String? posterPath;
  final String? imageUrl;
  final VoidCallback onTap;
  final FocusNode focusNode;
  final bool ensureVisible;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      focusNode: focusNode,
      onTap: onTap,
      focusedScale: 1.04,
      borderWidth: 2.5,
      ensureVisibleOnFocus: ensureVisible,
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Transform.scale(
                scale: 1.2,
                child: imageUrl != null && imageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        fadeInDuration: const Duration(milliseconds: 200),
                        errorWidget: (_, _, _) =>
                            const ColoredBox(color: AppColors.charcoalLight),
                      )
                    : PosterImage(
                        path: posterPath,
                        title: '',
                        displayWidth: 132,
                      ),
              ),
            ),
          ),
          const ColoredBox(color: Color(0xA6000000)),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'See more',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Continue Watching. Home uses one row. My Library uses two. Both scroll,
/// and See more appends the next titles at the end.
class ContinueWatchingRow extends ConsumerStatefulWidget {
  const ContinueWatchingRow({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    this.onFocus,
    this.firstItemFocusNode,
    this.autofocusFirst = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 40),
    this.rows = 1,
  });

  final String title;
  final List<WatchProgress> items;
  final void Function(WatchProgress p) onTap;
  final void Function(WatchProgress p)? onFocus;
  final FocusNode? firstItemFocusNode;
  final bool autofocusFirst;

  /// Home sits in an unpadded list. My Library already pads the page.
  final EdgeInsetsGeometry padding;
  final int rows;

  @override
  ConsumerState<ContinueWatchingRow> createState() =>
      _ContinueWatchingRowState();
}

class _ContinueWatchingRowState extends ConsumerState<ContinueWatchingRow> {
  final Set<String> _busy = {};

  void _loadVisible(int start, int shown) {
    if (shown <= 0 || start >= widget.items.length) return;
    final end = math.min(widget.items.length, start + shown);
    final fresh = <WatchProgress>[];
    for (var i = start; i < end; i++) {
      final p = widget.items[i];
      if (p.posterChecked) continue;
      final key = '${p.type}-${p.tmdbId}';
      if (_busy.add(key)) fresh.add(p);
    }
    if (fresh.isEmpty) return;
    ref.read(mediaRepositoryProvider).enrichPosters(fresh).whenComplete(() {
      for (final p in fresh) {
        _busy.remove('${p.type}-${p.tmdbId}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              widget.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          PagedPosterGrid(
            itemCount: widget.items.length,
            rows: widget.rows,
            firstItemFocusNode: widget.firstItemFocusNode,
            onVisible: _loadVisible,
            posterPath: (index) => widget.items[index].posterPath,
            itemBuilder: (context, index, lead, focusNode) {
              final p = widget.items[index];
              return _ContinueWatchingCard(
                progress: p,
                autofocus: lead && widget.autofocusFirst,
                focusNode: focusNode,
                onFocusChange: (f) {
                  if (f) widget.onFocus?.call(p);
                },
                onTap: () => widget.onTap(p),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ContinueWatchingCard extends StatelessWidget {
  const _ContinueWatchingCard({
    required this.progress,
    required this.onTap,
    this.onFocusChange,
    this.autofocus = false,
    this.focusNode,
  });

  final WatchProgress progress;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      onTap: onTap,
      autofocus: autofocus,
      focusNode: focusNode,
      onFocusChange: onFocusChange,
      focusedScale: 1.04,
      borderWidth: 2.5,
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PosterImage(
              path: progress.posterPath,
              title: progress.title ?? '',
              displayWidth: 130,
            ),
            if (progress.type == 'movie')
              Positioned(
                top: 6,
                right: 6,
                child: MovieWatchedBadge(tmdbId: progress.tmdbId),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 4,
                color: const Color(0x66000000),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress.watchedFraction,
                  child: Container(color: AppColors.textPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

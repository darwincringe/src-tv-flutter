import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/focus.dart';
import '../../core/theme.dart';
import '../../data/store/watch_progress.dart';
import 'poster_card.dart';

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

/// A poster grid that stays at [rows] rows. See more cards shift the window
/// forward or back by [step].
class PagedPosterGrid extends StatefulWidget {
  const PagedPosterGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.posterPath,
    this.rows = 3,
    this.step = 5,
    this.firstItemFocusNode,
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

  @override
  State<PagedPosterGrid> createState() => _PagedPosterGridState();
}

class _PagedPosterGridState extends State<PagedPosterGrid>
    with SingleTickerProviderStateMixin {
  static const double _extent = 132;
  static const double _gap = 14;
  static const Duration _slideDuration = Duration(milliseconds: 460);

  int _start = 0;
  int? _pendingStart;
  bool _animating = false;
  Widget? _cachedStrip;
  int? _cachedStart;
  bool _swapped = false;
  bool _forward = true;
  FocusNode? _pendingFocus;
  late final AnimationController _slide;
  final FocusNode _beginFocus = FocusNode(debugLabel: 'see-more-begin');
  final FocusNode _endFocus = FocusNode(debugLabel: 'see-more-end');
  final FocusNode _leadFocus = FocusNode(debugLabel: 'paged-lead');

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(vsync: this, duration: _slideDuration);
    _slide.addListener(_onSlideTick);
  }

  @override
  void dispose() {
    _slide.removeListener(_onSlideTick);
    _slide.dispose();
    _beginFocus.dispose();
    _endFocus.dispose();
    _leadFocus.dispose();
    super.dispose();
  }

  /// Halfway through, the outgoing cards are off-screen. The build swaps to
  /// the next window on that same frame so it slides in from the other side.
  void _onSlideTick() {
    if (_swapped || _pendingStart == null || _slide.value < 0.5) return;
    _swapped = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _pendingFocus;
      _pendingFocus = null;
      if (node != null && node.canRequestFocus) node.requestFocus();
    });
  }

  int get _visibleStart {
    if (_animating && _pendingStart != null && _slide.value >= 0.5) {
      return _pendingStart!;
    }
    return _start;
  }

  double _shift(double width) {
    if (!_animating) return 0;
    final t = _slide.value.clamp(0.0, 1.0);
    if (t < 0.5) {
      final u = Curves.easeIn.transform(t / 0.5);
      return (_forward ? -u : u) * width;
    }
    final u = Curves.easeOut.transform(((t - 0.5) / 0.5).clamp(0.0, 1.0));
    return (_forward ? (1 - u) : -(1 - u)) * width;
  }

  FocusNode get _leadNode => widget.firstItemFocusNode ?? _leadFocus;

  void _move(int total, int capacity, bool forward) {
    final current = posterWindow(
      start: _start,
      total: total,
      capacity: capacity,
    );
    final next = nextPosterStart(
      start: current.start,
      total: total,
      capacity: capacity,
      step: widget.step,
      forward: forward,
    );
    if (next == current.start && _start == current.start) return;
    final nextPage = posterWindow(
      start: next,
      total: total,
      capacity: capacity,
    );
    if (_animating) return;
    _forward = forward;
    _pendingStart = next;
    _pendingFocus = forward && !nextPage.canForward
        ? _beginFocus
        : !forward && !nextPage.canBack
            ? _leadNode
            : (forward ? _endFocus : _beginFocus);
    _swapped = false;
    _cachedStrip = null;
    _cachedStart = null;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _start = next);
      _pendingStart = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final node = _pendingFocus;
        _pendingFocus = null;
        if (node != null && node.canRequestFocus) node.requestFocus();
      });
      return;
    }
    setState(() => _animating = true);
    _slide.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        if (_pendingStart != null) _start = _pendingStart!;
        _pendingStart = null;
        _swapped = false;
        _animating = false;
      });
      _slide.value = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cols = math.max(1, (width / (_extent + _gap)).ceil());
        final capacity = cols * widget.rows;
        final total = widget.itemCount;
        return ClipRect(
          child: AnimatedBuilder(
            animation: _slide,
            builder: (context, _) => Transform.translate(
              offset: Offset(_shift(width), 0),
              child: _cachedPage(width, cols, capacity, total),
            ),
          ),
        );
      },
    );
  }

  Widget _cachedPage(double width, int cols, int capacity, int total) {
    if (!_animating) {
      _cachedStrip = null;
      _cachedStart = null;
      return _strip(width, cols, capacity, total, _start);
    }
    final start = _visibleStart;
    if (_cachedStrip == null || _cachedStart != start) {
      _cachedStart = start;
      _cachedStrip = _strip(width, cols, capacity, total, start);
    }
    return _cachedStrip!;
  }

  Widget _strip(double width, int cols, int capacity, int total, int start) {
    final page = posterWindow(start: start, total: total, capacity: capacity);
    final tiles = <Widget>[];
    if (page.canBack) {
      tiles.add(_seeMore(page.previousIndex, total, capacity, back: true));
    }
    for (var i = 0; i < page.shown; i++) {
      final index = page.start + i;
      final lead = i == 0 && page.start == 0;
      tiles.add(widget.itemBuilder(
        context,
        index,
        lead,
        lead ? _leadNode : null,
      ));
    }
    if (page.canForward) {
      tiles.add(_seeMore(page.nextIndex, total, capacity, back: false));
    }
    if (widget.rows <= 1) return _oneRow(width, cols, tiles);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      clipBehavior: Clip.none,
      padding: const EdgeInsets.symmetric(vertical: 6),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _extent,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: _gap,
        mainAxisSpacing: 16,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, i) => tiles[i],
    );
  }

  Widget _seeMore(int index, int total, int capacity, {required bool back}) {
    final path = index >= 0 && index < total ? widget.posterPath(index) : null;
    return SeeMorePoster(
      posterPath: path,
      focusNode: back ? _beginFocus : _endFocus,
      onTap: () => _move(total, capacity, !back),
    );
  }

  /// One horizontal strip. Cards keep poster size, and shrink only when the
  /// See more cards would otherwise wrap onto a second line.
  Widget _oneRow(double width, int cols, List<Widget> tiles) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    final natural = math.max(0.0, width - _gap * (cols - 1)) / cols;
    final cardWidth = tiles.length <= cols
        ? natural
        : math.max(0.0, width - _gap * (tiles.length - 1)) / tiles.length;
    final cardHeight = cardWidth * 3 / 2;
    return SizedBox(
      height: cardHeight,
      child: Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: tiles[i],
            ),
          ],
        ],
      ),
    );
  }
}

/// Poster-sized See more: the next (or previous) title, blurred and darkened,
/// with white "See more" in the middle.
class SeeMorePoster extends StatelessWidget {
  const SeeMorePoster({
    super.key,
    required this.posterPath,
    required this.onTap,
    required this.focusNode,
  });

  final String? posterPath;
  final VoidCallback onTap;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      focusNode: focusNode,
      onTap: onTap,
      focusedScale: 1.08,
      borderWidth: 3,
      ensureVisibleOnFocus: true,
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Transform.scale(
                scale: 1.2,
                child: PosterImage(
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

/// Continue Watching. Home uses one row; My Library keeps three. See more
/// shifts five titles so the row never grows.
class ContinueWatchingRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          PagedPosterGrid(
            itemCount: items.length,
            rows: rows,
            firstItemFocusNode: firstItemFocusNode,
            posterPath: (index) => items[index].posterPath,
            itemBuilder: (context, index, lead, focusNode) {
              final p = items[index];
              return _ContinueWatchingCard(
                progress: p,
                autofocus: lead && autofocusFirst,
                focusNode: focusNode,
                onFocusChange: (f) {
                  if (f) onFocus?.call(p);
                },
                onTap: () => onTap(p),
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
      focusedScale: 1.08,
      borderWidth: 3,
      ensureVisibleOnFocus: true,
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

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'continue_watching_row.dart';

class _Slot {
  const _Slot({required this.id, required this.rect, required this.child});

  final String id;
  final Rect rect;
  final Widget child;
}

/// First page shows [initial] titles. The first See more grows that to
/// [limit] without hiding any. Later pages stay at [limit] and step by 5.
PosterWindow titleWindow({
  required int start,
  required int total,
  required bool expanded,
  int initial = 5,
  int limit = 10,
}) {
  if (total <= 0 || limit <= 0) {
    return const PosterWindow(
      start: 0,
      shown: 0,
      canBack: false,
      canForward: false,
    );
  }
  final first = math.min(initial, total);
  if (!expanded || total <= initial) {
    return PosterWindow(
      start: 0,
      shown: first,
      canBack: false,
      canForward: first < total,
    );
  }
  if (total <= limit) {
    return PosterWindow(
      start: 0,
      shown: total,
      canBack: total > initial,
      canForward: false,
    );
  }
  final maxStart = total - limit;
  final clamped = start.clamp(0, maxStart);
  return PosterWindow(
    start: clamped,
    shown: limit,
    canBack: true,
    canForward: clamped + limit < total,
  );
}

/// Grows the first page from [initial] to [limit], then slides by [step].
({int start, bool expanded}) titleMove({
  required int start,
  required int total,
  required bool expanded,
  required bool forward,
  int initial = 5,
  int limit = 10,
  int step = 5,
}) {
  final page = titleWindow(
    start: start,
    total: total,
    expanded: expanded,
    initial: initial,
    limit: limit,
  );
  if (!forward) {
    if (!expanded || page.start <= 0 || total <= limit) {
      return (start: 0, expanded: false);
    }
    final maxStart = total - limit;
    return (
      start: (page.start - step).clamp(0, maxStart),
      expanded: true,
    );
  }
  if (!page.canForward) return (start: page.start, expanded: expanded);
  if (!expanded || total <= limit) return (start: 0, expanded: true);
  final maxStart = total - limit;
  return (
    start: (page.start + step).clamp(0, maxStart),
    expanded: true,
  );
}

/// A scrolling row of cards. See more appends the next titles and leaves the
/// ones already on screen where they are. There is no previous control.
class SlidingWindow extends StatefulWidget {
  const SlidingWindow({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.imageUrl,
    this.vertical = false,
    this.rows = 1,
    this.columns,
    this.step = 5,
    this.gap = 14,
    this.cardAspect = 2 / 3,
    this.extraHeight = 0,
    this.rowExtent = 112,
    this.titleLimit,
    this.initialTitles = 5,
    this.firstItemFocusNode,
  });

  final int itemCount;
  final Widget Function(
    BuildContext context,
    int index,
    bool lead,
    FocusNode? focusNode,
  ) itemBuilder;
  final String? Function(int index) imageUrl;

  /// One full-width column. [rows] is how many cells fit, including See more.
  final bool vertical;
  final int rows;
  final int? columns;
  final int step;
  final double gap;

  /// Width / height of the picture area when the window is a grid.
  final double cardAspect;
  final double extraHeight;
  final double rowExtent;

  /// When set, the first See more grows the page from [initialTitles] to this
  /// many titles. Later See more clicks keep this many and swap [step].
  final int? titleLimit;
  final int initialTitles;
  final FocusNode? firstItemFocusNode;

  @override
  State<SlidingWindow> createState() => _SlidingWindowState();
}

class _SlidingWindowState extends State<SlidingWindow> {
  bool _narrowPortrait = false;
  int? _portraitShown;
  final ScrollController _scroller = ScrollController();
  final FocusNode _beginFocus = FocusNode(debugLabel: 'window-see-more-begin');
  final FocusNode _endFocus = FocusNode(debugLabel: 'window-see-more-end');
  final FocusNode _leadFocus = FocusNode(debugLabel: 'window-lead');
  final Map<int, FocusNode> _itemFocus = {};

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
        () => FocusNode(debugLabel: 'window-$index'),
      );

  FocusNode get _leadNode => widget.firstItemFocusNode ?? _leadFocus;

  void _move(int total, int capacity, bool forward) {
    if (forward) _growPortrait(total);
  }


  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width <= 0) return const SizedBox.shrink();
        _narrowPortrait = width < 560;
        if (widget.vertical) return _appendColumn();
        return _portraitStrip(width);
      },
    );
  }

  /// Adds the next titles to the right. Cards already on screen do not move.
  void _growPortrait(int total) {
    final shown = _portraitShown ?? math.min(total, widget.initialTitles);
    if (shown >= total) return;
    final revealed = shown;
    _nodeFor(revealed);
    setState(() => _portraitShown = math.min(total, shown + widget.step));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _itemFocus[revealed];
      if (node != null && node.canRequestFocus) node.requestFocus();
    });
  }

  /// A vertical list that grows downward. See more stays under the last item.
  Widget _appendColumn() {
    final total = widget.itemCount;
    final shown = math.min(
      total,
      _portraitShown ?? math.min(total, widget.initialTitles),
    );
    _portraitShown = shown;
    if (shown <= 0) return const SizedBox.shrink();
    return SingleChildScrollView(
      child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown; i++)
          Padding(
            padding: EdgeInsets.only(bottom: widget.gap),
            child: SizedBox(
              height: widget.rowExtent,
              child: widget.itemBuilder(
                context,
                i,
                i == 0,
                _itemFocus[i] ?? (i == 0 ? _leadNode : null),
              ),
            ),
          ),
        if (shown < total)
          SizedBox(
            height: widget.rowExtent,
            child: SeeMorePoster(
              imageUrl: widget.imageUrl(shown),
              focusNode: _endFocus,
              ensureVisible: !_narrowPortrait,
              onTap: () => _growPortrait(total),
            ),
          ),
      ],
      ),
    );
  }

  /// The row scrolls. See more appends titles further along.
  Widget _portraitStrip(double width) {
    final total = widget.itemCount;
    final rows = math.max(1, widget.rows);
    final cols = math.max(
      1,
      widget.columns ?? (width / (132 + widget.gap)).floor(),
    );
    final cardWidth = _narrowPortrait
        ? math.min(280.0, math.max(180.0, width * 0.72))
        : math.max(120.0, (width - widget.gap * (cols - 1)) / cols);
    final cardHeight = cardWidth / widget.cardAspect + widget.extraHeight;
    final stride = cardWidth + widget.gap;
    const focusPad = 12.0;
    final shown = math.min(
      total,
      _portraitShown ?? math.min(total, widget.initialTitles),
    );
    _portraitShown = shown;
    if (shown <= 0) return const SizedBox.shrink();

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
        focusPad + col * stride,
        focusPad + row * (cardHeight + widget.gap),
        cardWidth,
        cardHeight,
      );
    }

    final placed = [
      for (var i = 0; i < ids.length; i++)
        _Slot(
          id: ids[i],
          rect: at(i),
          child: _childForId(ids[i], page, total, shown + 1),
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
    if (id == 'back' || id == 'forward') {
      var index = id == 'back' ? page.previousIndex : page.nextIndex;
      if (id == 'back' && index < 0 && page.shown > 0) {
        index = page.start + page.shown - 1;
      }
      final url = index >= 0 && index < total ? widget.imageUrl(index) : null;
      return SeeMorePoster(
        imageUrl: url,
        focusNode: id == 'back' ? _beginFocus : _endFocus,
        ensureVisible: !_narrowPortrait,
        onTap: () => _move(total, capacity, id == 'forward'),
      );
    }
    final index = int.parse(id.substring(1));
    final lead = index == 0 && page.start == 0;
    final node = _itemFocus[index] ?? (lead ? _leadNode : null);
    return widget.itemBuilder(context, index, lead, node);
  }
}

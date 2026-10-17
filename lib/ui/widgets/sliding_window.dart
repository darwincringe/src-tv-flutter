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

/// A fixed window of cards. See more is a blurred card of the next or previous
/// item, and only the cards that actually change places slide.
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

class _SlidingWindowState extends State<SlidingWindow>
    with SingleTickerProviderStateMixin {
  static const Duration _slideDuration = Duration(milliseconds: 380);

  int _start = 0;
  int? _pendingStart;
  bool _expanded = false;
  bool? _pendingExpanded;
  bool _animating = false;
  bool _forward = true;
  bool _narrowPortrait = false;
  double _stripStride = 194;
  double? _anchorScreenX;
  double? _anchorFromX;
  double? _anchorToX;
  bool _anchorSyncQueued = false;
  FocusNode? _pendingFocus;
  final ScrollController _scroller = ScrollController();
  final Map<String, Widget> _flying = {};
  late final AnimationController _slide;
  final FocusNode _beginFocus = FocusNode(debugLabel: 'window-see-more-begin');
  final FocusNode _endFocus = FocusNode(debugLabel: 'window-see-more-end');
  final FocusNode _leadFocus = FocusNode(debugLabel: 'window-lead');

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(vsync: this, duration: _slideDuration);
    _slide.addListener(_onSlide);
  }

  @override
  void dispose() {
    _slide.removeListener(_onSlide);
    _slide.dispose();
    _scroller.dispose();
    _beginFocus.dispose();
    _endFocus.dispose();
    _leadFocus.dispose();
    super.dispose();
  }

  FocusNode get _leadNode => widget.firstItemFocusNode ?? _leadFocus;

  void _move(int total, int capacity, bool forward) {
    final int next;
    final bool nextExpanded;
    final PosterWindow nextPage;
    if (widget.titleLimit != null) {
      final moved = titleMove(
        start: _start,
        total: total,
        expanded: _expanded,
        forward: forward,
        initial: widget.initialTitles,
        limit: widget.titleLimit!,
        step: widget.step,
      );
      if (moved.start == _start && moved.expanded == _expanded) return;
      next = moved.start;
      nextExpanded = moved.expanded;
      nextPage = titleWindow(
        start: next,
        total: total,
        expanded: nextExpanded,
        initial: widget.initialTitles,
        limit: widget.titleLimit!,
      );
    } else {
      final current = posterWindow(
        start: _start,
        total: total,
        capacity: capacity,
      );
      next = nextPosterStart(
        start: current.start,
        total: total,
        capacity: capacity,
        step: widget.step,
        forward: forward,
      );
      if (next == current.start && _start == current.start) return;
      nextExpanded = false;
      nextPage = posterWindow(start: next, total: total, capacity: capacity);
    }
    if (_animating) return;
    _forward = forward;
    _pendingStart = next;
    _pendingExpanded = widget.titleLimit == null ? null : nextExpanded;
    _pendingFocus = _narrowPortrait
        ? null
        : forward && !nextPage.canForward
            ? _beginFocus
            : !forward && !nextPage.canBack
                ? _leadNode
                : (forward ? _endFocus : _beginFocus);
    _flying.clear();
    if (_narrowPortrait) {
      _rememberAnchor(
        tapped: forward ? 'forward' : 'back',
        next: next,
        nextExpanded: nextExpanded,
        total: total,
        capacity: capacity,
      );
      if (MediaQuery.disableAnimationsOf(context)) {
        setState(() {
          _start = next;
          if (widget.titleLimit != null) _expanded = nextExpanded;
        });
        _pendingStart = null;
        _pendingExpanded = null;
        _scheduleAnchorSync(forceEnd: true);
        return;
      }
      setState(() => _animating = true);
      _slide.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        setState(() {
          if (_pendingStart != null) _start = _pendingStart!;
          if (_pendingExpanded != null) _expanded = _pendingExpanded!;
          _pendingStart = null;
          _pendingExpanded = null;
          _animating = false;
          _flying.clear();
        });
        _slide.value = 0;
        _scheduleAnchorSync(forceEnd: true);
      });
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() {
        _start = next;
        if (widget.titleLimit != null) _expanded = nextExpanded;
      });
      _pendingStart = null;
      _restoreFocus();
      return;
    }
    setState(() => _animating = true);
    _slide.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        if (_pendingStart != null) _start = _pendingStart!;
        if (_pendingExpanded != null) _expanded = _pendingExpanded!;
        _pendingStart = null;
        _pendingExpanded = null;
        _animating = false;
        _flying.clear();
      });
      _slide.value = 0;
      _restoreFocus();
    });
  }

  void _restoreFocus() {
    final node = _pendingFocus;
    _pendingFocus = null;
    if (node == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (node.canRequestFocus) node.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width <= 0) return const SizedBox.shrink();
        _narrowPortrait = !widget.vertical &&
            width < 560 &&
            MediaQuery.orientationOf(context) == Orientation.portrait;
        if (_narrowPortrait) {
          return _portraitStrip(width, _expanded);
        }
        final cols = widget.vertical
            ? 1
            : (widget.columns ??
                math.max(1, (width / (132 + widget.gap)).ceil()));
        final capacity = widget.vertical ? widget.rows : cols * widget.rows;
        return AnimatedBuilder(
          animation: _slide,
          builder: (context, _) {
            final placed = _placed(width, cols, capacity, _expanded);
            if (placed.isEmpty) return const SizedBox.shrink();
            final height = placed.map((s) => s.rect.bottom).reduce(math.max);
            return SizedBox(
              width: width,
              height: height,
              child: IgnorePointer(
                ignoring: _animating,
                child: Stack(
                  clipBehavior: _animating ? Clip.hardEdge : Clip.none,
                  children: [
                    for (final slot in placed)
                      Positioned.fromRect(rect: slot.rect, child: slot.child),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _onSlide() {
    if (!_narrowPortrait || !_animating) return;
    _scheduleAnchorSync(forceEnd: false);
  }

  void _scheduleAnchorSync({required bool forceEnd}) {
    if (_anchorSyncQueued) return;
    _anchorSyncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorSyncQueued = false;
      _syncAnchorScroll(forceEnd: forceEnd);
    });
  }

  void _rememberAnchor({
    required String tapped,
    required int next,
    required bool nextExpanded,
    required int total,
    required int capacity,
  }) {
    final fromX = _stripContentX(tapped, _start, _expanded, total, capacity);
    _anchorFromX = fromX;
    _anchorScreenX = fromX == null || !_scroller.hasClients
        ? null
        : fromX - _scroller.offset;
    final nextId = _anchorOnPage(tapped, next, nextExpanded, total, capacity);
    _anchorToX = _stripContentX(nextId, next, nextExpanded, total, capacity);
  }

  PosterWindow _stripPage(
    int start,
    bool expanded,
    int total,
    int capacity,
  ) {
    if (widget.titleLimit == null) {
      return posterWindow(start: start, total: total, capacity: capacity);
    }
    return titleWindow(
      start: start,
      total: total,
      expanded: expanded,
      initial: widget.initialTitles,
      limit: widget.titleLimit!,
    );
  }

  String _anchorOnPage(
    String tapped,
    int start,
    bool expanded,
    int total,
    int capacity,
  ) {
    final page = _stripPage(start, expanded, total, capacity);
    if (tapped == 'forward' && page.canForward) return 'forward';
    if (tapped == 'back' && page.canBack) return 'back';
    if (page.shown <= 0) return tapped;
    if (tapped == 'forward') return 'p${page.start + page.shown - 1}';
    return 'p${page.start}';
  }

  double? _stripContentX(
    String id,
    int start,
    bool expanded,
    int total,
    int capacity,
  ) {
    final page = _stripPage(start, expanded, total, capacity);
    final ids = <String>[];
    if (page.canBack) ids.add('back');
    for (var i = 0; i < page.shown; i++) {
      ids.add('p${page.start + i}');
    }
    if (page.canForward) ids.add('forward');
    final index = ids.indexOf(id);
    if (index < 0) return null;
    final col = index ~/ math.max(1, widget.rows);
    return col * _stripStride;
  }

  void _syncAnchorScroll({required bool forceEnd}) {
    final screen = _anchorScreenX;
    final from = _anchorFromX;
    final to = _anchorToX;
    if (screen == null || from == null || to == null || !_scroller.hasClients) {
      return;
    }
    final t = forceEnd
        ? 1.0
        : Curves.easeOutCubic.transform(_slide.value.clamp(0.0, 1.0));
    final x = from + (to - from) * t;
    final max = _scroller.position.maxScrollExtent;
    final target = (x - screen).clamp(0.0, max);
    if ((_scroller.offset - target).abs() > 0.5) {
      _scroller.jumpTo(target);
    }
  }

  /// Phone portrait scrolls the page. See more stays where it was tapped
  /// while the posters slide.
  Widget _portraitStrip(double width, bool expanded) {
    final total = widget.itemCount;
    final rows = math.max(1, widget.rows);
    final cardWidth = math.min(280.0, math.max(180.0, width * 0.72));
    final cardHeight = cardWidth / widget.cardAspect + widget.extraHeight;
    final pageCols = math.max(4, (width / (cardWidth + widget.gap)).ceil() + 2);
    final capacity = pageCols * rows;
    _stripStride = cardWidth + widget.gap;

    Rect at(int slot) {
      final col = slot ~/ rows;
      final row = slot % rows;
      return Rect.fromLTWH(
        col * _stripStride,
        row * (cardHeight + widget.gap),
        cardWidth,
        cardHeight,
      );
    }

    List<_Slot> slotsFor(int start, bool pageExpanded) {
      final page = _stripPage(start, pageExpanded, total, capacity);
      final ids = <String>[];
      if (page.canBack) ids.add('back');
      for (var i = 0; i < page.shown; i++) {
        ids.add('p${page.start + i}');
      }
      if (page.canForward) ids.add('forward');
      return [
        for (var i = 0; i < ids.length; i++)
          _Slot(
            id: ids[i],
            rect: at(i),
            child: _childForId(ids[i], page, total, capacity),
          ),
      ];
    }

    return AnimatedBuilder(
      animation: _slide,
      builder: (context, _) {
        final current = slotsFor(_start, expanded);
        final incoming = _animating && _pendingStart != null
            ? slotsFor(_pendingStart!, _pendingExpanded ?? expanded)
            : null;
        final placed = incoming == null
            ? current
            : _slideHorizontal(
                current,
                incoming,
                (_scroller.hasClients ? _scroller.offset : 0) + width,
              );
        if (placed.isEmpty) return const SizedBox.shrink();
        final contentWidth = [
          ...current,
          ...?incoming,
          ...placed,
        ].map((slot) => slot.rect.right).reduce(math.max);
        final height = placed.map((slot) => slot.rect.bottom).reduce(math.max);
        return SizedBox(
          width: width,
          height: height,
          child: SingleChildScrollView(
            controller: _scroller,
            scrollDirection: Axis.horizontal,
            physics: _animating ? const NeverScrollableScrollPhysics() : null,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: math.max(width, contentWidth),
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final slot in placed)
                    Positioned.fromRect(rect: slot.rect, child: slot.child),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<_Slot> _placed(double width, int cols, int capacity, bool expanded) {
    final current = _slotsFor(_start, width, cols, capacity, expanded);
    final nextStart = _animating ? _pendingStart : null;
    if (nextStart == null) return current;
    final incoming = _slotsFor(
      nextStart,
      width,
      cols,
      capacity,
      _pendingExpanded ?? expanded,
    );
    return widget.vertical
        ? _slideVertical(current, incoming, _stackHeight(current))
        : _slideHorizontal(current, incoming, width);
  }

  double _stackHeight(List<_Slot> slots) {
    if (slots.isEmpty) return widget.rowExtent;
    return slots.map((s) => s.rect.bottom).reduce(math.max);
  }

  List<_Slot> _slideHorizontal(List<_Slot> from, List<_Slot> to, double width) {
    final t = Curves.easeOutCubic.transform(_slide.value.clamp(0.0, 1.0));
    final oldRect = {for (final slot in from) slot.id: slot.rect};
    final newRect = {for (final slot in to) slot.id: slot.rect};
    final oldChild = {for (final slot in from) slot.id: slot.child};
    final newChild = {for (final slot in to) slot.id: slot.child};
    final stride = from.isEmpty ? 146.0 : from.first.rect.width + widget.gap;

    Offset primary = Offset(-stride * widget.step, 0);
    if (!_forward) primary = Offset(stride * widget.step, 0);
    for (final slot in to) {
      if (!slot.id.startsWith('p') || !oldRect.containsKey(slot.id)) continue;
      final old = oldRect[slot.id]!;
      if ((slot.rect.top - old.top).abs() < 1) {
        primary = slot.rect.topLeft - old.topLeft;
        break;
      }
    }

    final ids = <String>{...oldRect.keys, ...newRect.keys};
    final leaving = ids.where((id) => !newRect.containsKey(id)).toList();
    final arriving = ids.where((id) => !oldRect.containsKey(id)).toList();
    final moved = <_Slot>[];

    for (final id in ids) {
      final child = _flying.putIfAbsent(id, () => newChild[id] ?? oldChild[id]!);
      final Rect begin;
      final Rect end;
      if (id == 'back' || id == 'forward') {
        final edge = id == 'back' ? -1.0 : 1.0;
        if (oldRect.containsKey(id) && newRect.containsKey(id)) {
          begin = oldRect[id]!;
          end = newRect[id]!;
        } else if (oldRect.containsKey(id)) {
          begin = oldRect[id]!;
          end = begin.shift(Offset(edge * (begin.width + widget.gap), 0));
        } else {
          end = newRect[id]!;
          begin = end.shift(Offset(edge * (end.width + widget.gap), 0));
        }
      } else if (oldRect.containsKey(id) && newRect.containsKey(id)) {
        begin = oldRect[id]!;
        end = newRect[id]!;
      } else if (oldRect.containsKey(id)) {
        begin = oldRect[id]!;
        final order = leaving.indexOf(id);
        final left = _forward
            ? math.min(
                begin.shift(primary).left,
                -begin.width - widget.gap - order * stride,
              )
            : math.max(
                begin.shift(primary).left,
                width + widget.gap + order * stride,
              );
        end = Rect.fromLTWH(left, begin.top, begin.width, begin.height);
      } else {
        end = newRect[id]!;
        final natural = end.shift(Offset(-primary.dx, -primary.dy));
        final inside = _forward ? natural.left < width : natural.right > 0;
        if (!inside) {
          begin = natural;
        } else if (_forward) {
          final order = arriving.indexOf(id);
          begin = Rect.fromLTWH(
            width + widget.gap + order * stride,
            end.top,
            end.width,
            end.height,
          );
        } else {
          final order = arriving.indexOf(id);
          begin = Rect.fromLTWH(
            -end.width - widget.gap - order * stride,
            end.top,
            end.width,
            end.height,
          );
        }
      }
      moved.add(_Slot(id: id, rect: Rect.lerp(begin, end, t)!, child: child));
    }
    moved.sort((a, b) => a.rect.left.compareTo(b.rect.left));
    return moved;
  }

  List<_Slot> _slideVertical(List<_Slot> from, List<_Slot> to, double height) {
    final t = Curves.easeOutCubic.transform(_slide.value.clamp(0.0, 1.0));
    final oldRect = {for (final slot in from) slot.id: slot.rect};
    final newRect = {for (final slot in to) slot.id: slot.rect};
    final oldChild = {for (final slot in from) slot.id: slot.child};
    final newChild = {for (final slot in to) slot.id: slot.child};
    final stride = from.isEmpty ? widget.rowExtent + widget.gap : from.first.rect.height + widget.gap;

    var primary = -stride * widget.step;
    if (!_forward) primary = stride * widget.step;
    for (final slot in to) {
      if (!slot.id.startsWith('p') || !oldRect.containsKey(slot.id)) continue;
      primary = slot.rect.top - oldRect[slot.id]!.top;
      break;
    }

    final ids = <String>{...oldRect.keys, ...newRect.keys};
    final leaving = ids.where((id) => !newRect.containsKey(id)).toList();
    final arriving = ids.where((id) => !oldRect.containsKey(id)).toList();
    final moved = <_Slot>[];

    for (final id in ids) {
      final child = _flying.putIfAbsent(id, () => newChild[id] ?? oldChild[id]!);
      final Rect begin;
      final Rect end;
      if (id == 'back' || id == 'forward') {
        final edge = id == 'back' ? -1.0 : 1.0;
        if (oldRect.containsKey(id) && newRect.containsKey(id)) {
          begin = oldRect[id]!;
          end = newRect[id]!;
        } else if (oldRect.containsKey(id)) {
          begin = oldRect[id]!;
          end = begin.shift(Offset(0, edge * stride));
        } else {
          end = newRect[id]!;
          begin = end.shift(Offset(0, edge * stride));
        }
      } else if (oldRect.containsKey(id) && newRect.containsKey(id)) {
        begin = oldRect[id]!;
        end = newRect[id]!;
      } else if (oldRect.containsKey(id)) {
        begin = oldRect[id]!;
        final order = leaving.indexOf(id);
        final top = _forward
            ? math.min(begin.top + primary, -begin.height - widget.gap - order * stride)
            : math.max(begin.top + primary, height + widget.gap + order * stride);
        end = Rect.fromLTWH(begin.left, top, begin.width, begin.height);
      } else {
        end = newRect[id]!;
        final naturalTop = end.top - primary;
        final inside = _forward ? naturalTop < height : naturalTop + end.height > 0;
        if (!inside) {
          begin = Rect.fromLTWH(end.left, naturalTop, end.width, end.height);
        } else if (_forward) {
          final order = arriving.indexOf(id);
          begin = Rect.fromLTWH(
            end.left,
            height + widget.gap + order * stride,
            end.width,
            end.height,
          );
        } else {
          final order = arriving.indexOf(id);
          begin = Rect.fromLTWH(
            end.left,
            -end.height - widget.gap - order * stride,
            end.width,
            end.height,
          );
        }
      }
      moved.add(_Slot(id: id, rect: Rect.lerp(begin, end, t)!, child: child));
    }
    moved.sort((a, b) => a.rect.top.compareTo(b.rect.top));
    return moved;
  }

  List<_Slot> _slotsFor(
    int start,
    double width,
    int cols,
    int capacity,
    bool expanded,
  ) {
    final total = widget.itemCount;
    final page = widget.titleLimit == null
        ? posterWindow(start: start, total: total, capacity: capacity)
        : titleWindow(
            start: start,
            total: total,
            expanded: expanded,
            initial: widget.initialTitles,
            limit: widget.titleLimit!,
          );
    final ids = <String>[];
    if (page.canBack) ids.add('back');
    for (var i = 0; i < page.shown; i++) {
      ids.add('p${page.start + i}');
    }
    if (page.canForward) ids.add('forward');
    if (ids.isEmpty) return const [];

    final Rect Function(int slot) at;
    if (widget.vertical) {
      final h = widget.rowExtent;
      at = (slot) => Rect.fromLTWH(0, slot * (h + widget.gap), width, h);
    } else {
      final fit = widget.rows <= 1 ? math.max(cols, ids.length) : cols;
      final cardWidth = math.max(0.0, width - widget.gap * (fit - 1)) / fit;
      final cardHeight = cardWidth / widget.cardAspect + widget.extraHeight;
      final layoutCols = widget.rows <= 1 ? fit : cols;
      at = (slot) {
        final col = widget.rows <= 1 ? slot : slot % layoutCols;
        final row = widget.rows <= 1 ? 0 : slot ~/ layoutCols;
        return Rect.fromLTWH(
          col * (cardWidth + widget.gap),
          row * (cardHeight + widget.gap),
          cardWidth,
          cardHeight,
        );
      };
    }

    return [
      for (var i = 0; i < ids.length; i++)
        _Slot(
          id: ids[i],
          rect: at(i),
          child: _childForId(ids[i], page, total, capacity),
        ),
    ];
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
        onTap: () => _move(total, capacity, id == 'forward'),
      );
    }
    final index = int.parse(id.substring(1));
    final lead = index == 0 && page.start == 0;
    return widget.itemBuilder(context, index, lead, lead ? _leadNode : null);
  }
}

import 'package:flutter/material.dart';

/// Where a 10-episode page starts after moving [step] titles.
/// The last page stays full, so the final step can be shorter than [step].
int episodePageStart({
  required int start,
  required int total,
  required bool forward,
  int limit = 10,
  int step = 5,
}) {
  if (total <= limit || limit <= 0) return 0;
  final maxStart = total - limit;
  final current = start.clamp(0, maxStart);
  final next = forward ? current + step : current - step;
  return next.clamp(0, maxStart);
}

/// Shows [limit] episodes and steps by [step]. See more rows are extra, so
/// they do not replace an episode.
class EpisodeWindow extends StatefulWidget {
  const EpisodeWindow({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.seeMoreBuilder,
    this.limit = 10,
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
  final Widget Function(
    BuildContext context,
    int index,
    FocusNode focusNode,
    VoidCallback onTap,
  ) seeMoreBuilder;
  final int limit;
  final int step;
  final FocusNode? firstItemFocusNode;

  @override
  State<EpisodeWindow> createState() => _EpisodeWindowState();
}

class _EpisodeWindowState extends State<EpisodeWindow>
    with SingleTickerProviderStateMixin {
  int _start = 0;
  bool _forward = true;
  bool _animating = false;
  late final AnimationController _slide;
  final FocusNode _beginFocus = FocusNode(debugLabel: 'episode-see-more-begin');
  final FocusNode _endFocus = FocusNode(debugLabel: 'episode-see-more-end');

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
  }

  @override
  void dispose() {
    _slide.dispose();
    _beginFocus.dispose();
    _endFocus.dispose();
    super.dispose();
  }

  int get _maxStart {
    if (widget.itemCount <= widget.limit) return 0;
    return widget.itemCount - widget.limit;
  }

  void _move(bool forward) {
    final next = episodePageStart(
      start: _start,
      total: widget.itemCount,
      forward: forward,
      limit: widget.limit,
      step: widget.step,
    );
    if (next == _start || _animating) return;
    _forward = forward;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _start = next);
      _focusAfter(next);
      return;
    }
    setState(() => _animating = true);
    _slide.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _start = next;
        _animating = false;
      });
      _slide.value = 0;
      _focusAfter(next);
    });
  }

  void _focusAfter(int start) {
    final node = start > 0
        ? _beginFocus
        : (widget.firstItemFocusNode ?? _endFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (node.canRequestFocus) node.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final start = _start.clamp(0, _maxStart);
    final preview = _animating
        ? episodePageStart(
            start: start,
            total: widget.itemCount,
            forward: _forward,
            limit: widget.limit,
            step: widget.step,
          )
        : start;
    return ClipRect(
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_slide.value.clamp(0.0, 1.0));
          final dy = _animating ? (1 - t) * (_forward ? 24.0 : -24.0) : 0.0;
          return Transform.translate(
            offset: Offset(0, dy),
            child: Opacity(
              opacity: _animating ? 0.65 + 0.35 * t : 1,
              child: _column(preview),
            ),
          );
        },
      ),
    );
  }

  Widget _column(int start) {
    final end = (start + widget.limit).clamp(0, widget.itemCount);
    final children = <Widget>[];
    if (start > 0) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: widget.seeMoreBuilder(
          context,
          start - 1,
          _beginFocus,
          () => _move(false),
        ),
      ));
    }
    for (var i = start; i < end; i++) {
      final lead = i == 0 && start == 0;
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: widget.itemBuilder(
          context,
          i,
          lead,
          lead ? widget.firstItemFocusNode : null,
        ),
      ));
    }
    if (end < widget.itemCount) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: widget.seeMoreBuilder(
          context,
          end,
          _endFocus,
          () => _move(true),
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

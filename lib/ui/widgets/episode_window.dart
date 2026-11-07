import 'dart:math' as math;

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

/// Shows the first [limit] episodes. See more appends [step] more below the
/// ones already on screen. There is no previous control.
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

class _EpisodeWindowState extends State<EpisodeWindow> {
  int? _shown;
  final FocusNode _endFocus = FocusNode(debugLabel: 'episode-see-more-end');
  final Map<int, FocusNode> _itemFocus = {};

  @override
  void dispose() {
    _endFocus.dispose();
    for (final node in _itemFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _nodeFor(int index) => _itemFocus.putIfAbsent(
        index,
        () => FocusNode(debugLabel: 'episode-$index'),
      );

  void _grow() {
    final total = widget.itemCount;
    final shown = _shown ?? math.min(total, widget.limit);
    if (shown >= total) return;
    final revealed = shown;
    _nodeFor(revealed);
    setState(() => _shown = math.min(total, shown + widget.step));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _itemFocus[revealed];
      if (node != null && node.canRequestFocus) node.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.itemCount;
    final shown = math.min(total, _shown ?? math.min(total, widget.limit));
    _shown = shown;
    final children = <Widget>[];
    for (var i = 0; i < shown; i++) {
      final lead = i == 0;
      final node = _itemFocus[i] ?? (lead ? widget.firstItemFocusNode : null);
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: widget.itemBuilder(
          context,
          i,
          lead,
          node,
        ),
      ));
    }
    if (shown < total) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: widget.seeMoreBuilder(
          context,
          shown,
          _endFocus,
          _grow,
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

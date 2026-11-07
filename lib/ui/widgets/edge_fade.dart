import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Fades the leading and trailing edges of a scroll view so a poster that is
/// halfway out of view dissolves into the page instead of being sliced off.
/// An edge that has nothing hidden stays solid.
class EdgeFade extends StatefulWidget {
  const EdgeFade({
    super.key,
    required this.controller,
    required this.child,
    this.axis = Axis.horizontal,
  });

  final ScrollController controller;
  final Axis axis;
  final Widget child;

  @override
  State<EdgeFade> createState() => _EdgeFadeState();
}

class _EdgeFadeState extends State<EdgeFade> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void didUpdateWidget(EdgeFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _canBack {
    if (!widget.controller.hasClients) return false;
    return widget.controller.position.pixels > 1;
  }

  bool get _canForward {
    if (!widget.controller.hasClients) return false;
    final position = widget.controller.position;
    return position.maxScrollExtent - position.pixels > 1;
  }

  @override
  Widget build(BuildContext context) {
    final back = _canBack;
    final forward = _canForward;
    if (!back && !forward) return widget.child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = widget.axis == Axis.horizontal;
        final span =
            horizontal ? constraints.maxWidth : constraints.maxHeight;
        final fade = span.isFinite
            ? math.min(160.0, span * 0.22).clamp(72.0, 160.0)
            : 120.0;
        return Stack(
          children: [
            widget.child,
            if (back)
              Positioned(
                left: horizontal ? 0 : null,
                top: 0,
                right: horizontal ? null : 0,
                bottom: horizontal ? 0 : null,
                width: horizontal ? fade : null,
                height: horizontal ? null : fade,
                child: _EdgeScrim(axis: widget.axis, leading: true),
              ),
            if (forward)
              Positioned(
                left: horizontal ? null : 0,
                top: horizontal ? 0 : null,
                right: 0,
                bottom: 0,
                width: horizontal ? fade : null,
                height: horizontal ? null : fade,
                child: _EdgeScrim(axis: widget.axis, leading: false),
              ),
          ],
        );
      },
    );
  }
}

/// Fades the top of a vertical list once it has scrolled, so a row leaving
/// the page dissolves instead of being cut off against the hero.
class TopEdgeFade extends StatefulWidget {
  const TopEdgeFade({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  State<TopEdgeFade> createState() => _TopEdgeFadeState();
}

class _TopEdgeFadeState extends State<TopEdgeFade> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void didUpdateWidget(TopEdgeFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _scrolled {
    if (!widget.controller.hasClients) return false;
    return widget.controller.position.pixels > 1;
  }

  @override
  Widget build(BuildContext context) {
    if (!_scrolled) return widget.child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final span = constraints.maxHeight;
        final fade = span.isFinite
            ? math.min(170.0, span * 0.28).clamp(96.0, 170.0)
            : 140.0;
        return Stack(
          children: [
            widget.child,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: fade,
              child: const _EdgeScrim(axis: Axis.vertical, leading: true),
            ),
          ],
        );
      },
    );
  }
}

class _EdgeScrim extends StatelessWidget {
  const _EdgeScrim({required this.axis, required this.leading});

  final Axis axis;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == Axis.horizontal;
    final begin = horizontal
        ? (leading ? Alignment.centerLeft : Alignment.centerRight)
        : (leading ? Alignment.topCenter : Alignment.bottomCenter);
    final end = horizontal
        ? (leading ? Alignment.centerRight : Alignment.centerLeft)
        : (leading ? Alignment.bottomCenter : Alignment.topCenter);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: begin,
            end: end,
            colors: const [
              AppColors.charcoal,
              Color(0xE6161616),
              Color(0x00161616),
            ],
            stops: const [0.0, 0.38, 1.0],
          ),
        ),
      ),
    );
  }
}

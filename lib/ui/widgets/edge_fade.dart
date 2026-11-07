import 'package:flutter/material.dart';

/// Fades the leading and trailing edges of a scroll view instead of cutting
/// the card that is halfway out of view. An edge that has nothing hidden
/// stays solid.
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
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final span = widget.axis == Axis.horizontal ? rect.width : rect.height;
        final fade = span <= 0 ? 0.0 : (36 / span).clamp(0.0, 0.18);
        return LinearGradient(
          begin: widget.axis == Axis.horizontal
              ? Alignment.centerLeft
              : Alignment.topCenter,
          end: widget.axis == Axis.horizontal
              ? Alignment.centerRight
              : Alignment.bottomCenter,
          colors: [
            back ? Colors.transparent : Colors.black,
            Colors.black,
            Colors.black,
            forward ? Colors.transparent : Colors.black,
          ],
          stops: [0, fade, 1 - fade, 1],
        ).createShader(rect);
      },
      child: widget.child,
    );
  }
}

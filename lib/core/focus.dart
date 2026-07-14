import 'package:flutter/material.dart';

import 'theme.dart';

/// A card that works with both D-pad focus (TV) and touch (phone). On focus it
/// scales up and draws a white border — the focus treatment used throughout the
/// Kotlin app. Pressing Select/Enter or tapping invokes [onTap].
class FocusableCard extends StatefulWidget {
  const FocusableCard({
    super.key,
    required this.child,
    this.onTap,
    this.focusedScale = 1.08,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.borderWidth = 2.5,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
    this.showBorder = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double focusedScale;
  final BorderRadius borderRadius;
  final double borderWidth;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final bool showBorder;

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard> {
  bool _focused = false;

  void _setFocus(bool f) {
    if (_focused == f) return;
    setState(() => _focused = f);
    widget.onFocusChange?.call(f);
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _setFocus,
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _focused ? widget.focusedScale : 1.0,
          duration: const Duration(milliseconds: 120),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              border: widget.showBorder
                  ? Border.all(
                      color: _focused
                          ? AppColors.textPrimary
                          : Colors.transparent,
                      width: widget.borderWidth,
                    )
                  : null,
            ),
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

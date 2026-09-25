import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Wraps a text field so D-pad Up/Down move focus OUT of it. Text fields
/// otherwise consume the arrow keys (to move the caret), which traps focus on
/// the field and stops a TV remote from reaching the next field or the results
/// below. Left/Right still reach the field for caret movement.
class DpadFieldFocus extends StatelessWidget {
  const DpadFieldFocus({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false, // never a focus target itself; just intercepts
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        TraversalDirection? dir;
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          dir = TraversalDirection.down;
        } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          dir = TraversalDirection.up;
        }
        if (dir == null) return KeyEventResult.ignored;
        final moved =
            FocusManager.instance.primaryFocus?.focusInDirection(dir) ?? false;
        return moved ? KeyEventResult.handled : KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

/// A white focus ring drawn a few px OUTSIDE [child] (with a transparent gap)
/// when [focused]. The gap makes it read clearly even over a light/filled
/// button, where a flush border would blend in. No glow — border only.
class FocusRing extends StatelessWidget {
  const FocusRing({
    super.key,
    required this.focused,
    required this.child,
    this.radius = 10,
    this.gap = 3,
    this.width = 3,
  });

  final bool focused;
  final Widget child;
  final double radius;
  final double gap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.all(gap),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: focused ? AppColors.focusRing : Colors.transparent,
          width: width,
        ),
      ),
      child: child,
    );
  }
}

/// A card that works with both D-pad focus (TV) and touch (phone). On focus it
/// scales up and draws a white border — the focus treatment used throughout the
/// Kotlin app. Pressing Select/Enter or tapping invokes [onTap].
class FocusableCard extends StatefulWidget {
  const FocusableCard({
    super.key,
    required this.child,
    this.onTap,
    this.focusedScale = 1.12,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.borderWidth = 4,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
    this.showBorder = true,
    this.ensureVisibleOnFocus = false,
    this.ensureVisibleAlignment = 0.35,
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

  /// When true, focusing this card scrolls its enclosing scrollable(s) so the
  /// card is comfortably in view (with headroom) instead of being jammed against
  /// the viewport edge — essential for D-pad navigation on TV.
  final bool ensureVisibleOnFocus;
  final double ensureVisibleAlignment;

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard> {
  bool _focused = false;

  void _setFocus(bool f) {
    if (_focused == f) return;
    setState(() => _focused = f);
    widget.onFocusChange?.call(f);
    if (f && widget.ensureVisibleOnFocus) {
      // Shortly after the framework's own directional-focus scroll, so our
      // alignment (with headroom for titles/edges) is the one that sticks.
      Future.delayed(const Duration(milliseconds: 80), () {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: widget.ensureVisibleAlignment,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _setFocus,
      mouseCursor: SystemMouseCursors.click,
      // Map Enter/Space (keyboard) + Select (D-pad center) to activation, so a
      // focused card is selectable by keyboard on web/desktop as well as by a
      // TV remote — not only by mouse/touch tap.
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
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
        // Isolate the focus scale/border tween to this card's own layer so it
        // doesn't repaint the whole row + hero backdrop on every focus hop.
        child: RepaintBoundary(
          child: AnimatedScale(
            scale: _focused ? widget.focusedScale : 1.0,
            duration: const Duration(milliseconds: 120),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                border: widget.showBorder
                    ? Border.all(
                        color: _focused
                            ? AppColors.focusRing
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
      ),
    );
  }
}

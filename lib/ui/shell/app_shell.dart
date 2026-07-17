import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// Navigation items, top-to-bottom / left-to-right, matching the Kotlin
/// `RailItem` order: Search, Home, Movies, TV Series, Settings.
const _navItems = <_NavSpec>[
  _NavSpec(Icons.search, 'Search'),
  _NavSpec(Icons.home_filled, 'Home'),
  _NavSpec(Icons.movie_outlined, 'Movies'),
  _NavSpec(Icons.live_tv_outlined, 'TV Series'),
  _NavSpec(Icons.settings_outlined, 'Settings'),
];

class _NavSpec {
  final IconData icon;
  final String label;
  const _NavSpec(this.icon, this.label);
}

/// App shell hosting the branch content plus the nav rail (landscape/TV) or
/// bottom bar (portrait). Mirrors the Kotlin `NavRail` + `SrcTvApp` layout.
///
/// D-pad handling: go_router gives each branch its own Navigator (a separate
/// FocusScope), so directional focus can't naturally cross from the content into
/// the rail. We bridge that gap explicitly — Left at the content's left edge
/// jumps to the rail, Right on the rail returns to where you were.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final List<FocusNode> _railNodes = List.generate(
    _navItems.length,
    (i) => FocusNode(debugLabel: 'rail-${_navItems[i].label}'),
  );

  // The content node that had focus when we last jumped to the rail, so Right
  // on the rail can hand focus straight back to it.
  FocusNode? _lastContentFocus;

  @override
  void dispose() {
    for (final n in _railNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _onSelect(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  void _focusRail() {
    final i = widget.navigationShell.currentIndex.clamp(0, _railNodes.length - 1);
    _railNodes[i].requestFocus();
  }

  // Left from content: try to move within the content first; only when already
  // at the left edge do we hop over to the rail.
  KeyEventResult _onContentKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    final pf = FocusManager.instance.primaryFocus;
    final moved = pf?.focusInDirection(TraversalDirection.left) ?? false;
    if (!moved) {
      _lastContentFocus = pf;
      _focusRail();
    }
    return KeyEventResult.handled;
  }

  // Right from the rail: return to the content we came from, else fall back to
  // directional movement into the content area.
  KeyEventResult _onRailKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    final last = _lastContentFocus;
    if (last != null && last.context != null && last.canRequestFocus) {
      last.requestFocus();
    } else {
      FocusManager.instance.primaryFocus
          ?.focusInDirection(TraversalDirection.right);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final portrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final current = widget.navigationShell.currentIndex;

    final buttons = [
      for (var i = 0; i < _navItems.length; i++)
        _NavButton(
          spec: _navItems[i],
          selected: i == current,
          focusNode: _railNodes[i],
          onTap: () => _onSelect(i),
        ),
    ];

    final content = Focus(
      onKeyEvent: _onContentKey,
      canRequestFocus: false, // ancestor bridge only; never holds focus itself
      child: widget.navigationShell,
    );

    if (portrait) {
      return Scaffold(
        backgroundColor: AppColors.charcoal,
        body: Column(
          children: [
            Expanded(child: content),
            Focus(
              onKeyEvent: _onRailKey,
              canRequestFocus: false,
              child: Container(
                height: 60,
                color: AppColors.railBlack,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: buttons,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      body: Row(
        children: [
          Focus(
            onKeyEvent: _onRailKey,
            canRequestFocus: false,
            child: Container(
              width: 60,
              color: AppColors.railBlack,
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final b in buttons) ...[
                    b,
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  const _NavButton({
    required this.spec,
    required this.selected,
    required this.onTap,
    this.focusNode,
  });
  final _NavSpec spec;
  final bool selected;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // Focused → bright amber disc (the app-wide D-pad treatment). Otherwise the
    // icon tint alone signals which tab is currently selected.
    final bg = _focused ? AppColors.focusRing : Colors.transparent;
    final fg = _focused
        ? Colors.black
        : (widget.selected ? AppColors.textPrimary : AppColors.textSecondary);

    return FocusableActionDetector(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.spec.label,
          child: AnimatedScale(
            scale: _focused ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
              ),
              child: Icon(widget.spec.icon, size: 20, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
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
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  void _onSelect(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final portrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final current = navigationShell.currentIndex;

    final buttons = [
      for (var i = 0; i < _navItems.length; i++)
        _NavButton(
          spec: _navItems[i],
          selected: i == current,
          onTap: () => _onSelect(i),
        ),
    ];

    if (portrait) {
      return Scaffold(
        backgroundColor: AppColors.charcoal,
        body: Column(
          children: [
            Expanded(child: navigationShell),
            Container(
              height: 60,
              color: AppColors.railBlack,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: buttons,
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
          Container(
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
          Expanded(child: navigationShell),
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
  });
  final _NavSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused; // inverts on focus/press
    final bg = active ? AppColors.textPrimary : Colors.transparent;
    final fg = active
        ? AppColors.charcoal
        : (widget.selected ? AppColors.textPrimary : AppColors.textSecondary);

    return FocusableActionDetector(
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(widget.spec.icon, size: 20, color: fg),
          ),
        ),
      ),
    );
  }
}

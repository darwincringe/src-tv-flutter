import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/focus.dart';
import '../../core/theme.dart';
import '../../data/store/watch_progress.dart';
import 'poster_card.dart';

/// Continue Watching row: poster cards with a watched-progress bar. Reveals
/// [_pageSize] at a time and **seamlessly** loads the next batch as the user
/// nears the end (on focus or scroll) — no "More" button.
class ContinueWatchingRow extends StatefulWidget {
  const ContinueWatchingRow({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    this.onFocus,
    this.firstItemFocusNode,
    this.autofocusFirst = false,
  });

  final String title;
  final List<WatchProgress> items;
  final void Function(WatchProgress p) onTap;
  final void Function(WatchProgress p)? onFocus;
  final FocusNode? firstItemFocusNode;
  final bool autofocusFirst;

  @override
  State<ContinueWatchingRow> createState() => _ContinueWatchingRowState();
}

class _ContinueWatchingRowState extends State<ContinueWatchingRow> {
  static const int _pageSize = 10;
  static const int _webCap = 20;
  // Web mouse drag-scroll is unreliable, so show up to [_webCap] upfront (all
  // reachable by wheel) instead of the drag-triggered lazy load.
  int _visible = kIsWeb ? _webCap : _pageSize;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  // Touch/drag path: reveal the next page as the row nears its end.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _loadMore() {
    if (kIsWeb) return; // web shows up to _webCap upfront; no drag-lazy-load
    if (_visible < widget.items.length) {
      setState(() => _visible += _pageSize);
    }
  }

  // Scroll the whole section (title + row) into view when a card is focused, so
  // the title isn't clipped and the row snaps near the top for D-pad nav.
  void _ensureSectionVisible() {
    // Shortly after the framework's own directional-focus scroll, so our
    // section-level alignment (title included) is the one that sticks.
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.08,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final shown = _visible.clamp(0, total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 40, bottom: 6),
          child: Text(
            widget.title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            // Don't clip the focus scale-up of the cards.
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
            itemCount: shown,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final p = widget.items[index];
              return _ContinueWatchingCard(
                progress: p,
                autofocus: index == 0 && widget.autofocusFirst,
                focusNode: index == 0 ? widget.firstItemFocusNode : null,
                onFocusChange: (f) {
                  if (f) {
                    widget.onFocus?.call(p);
                    _ensureSectionVisible();
                    // Seamlessly reveal the next page before the user reaches
                    // the very end (D-pad path).
                    if (index >= shown - 2) _loadMore();
                  }
                },
                onTap: () => widget.onTap(p),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ContinueWatchingCard extends StatelessWidget {
  const _ContinueWatchingCard({
    required this.progress,
    required this.onTap,
    this.onFocusChange,
    this.autofocus = false,
    this.focusNode,
  });

  final WatchProgress progress;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    // No title / "S1·E2" label here anymore — the focused item's title and
    // season/episode are shown in the hero at the top. Just the poster + the
    // watched-progress bar.
    return SizedBox(
      width: 130,
      child: FocusableCard(
        onTap: onTap,
        autofocus: autofocus,
        focusNode: focusNode,
        onFocusChange: onFocusChange,
        focusedScale: 1.08,
        borderWidth: 3,
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PosterImage(
                path: progress.posterPath,
                title: progress.title ?? '',
                displayWidth: 130,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 4,
                  color: const Color(0x66000000),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress.watchedFraction,
                    child: Container(color: AppColors.textPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


import 'package:flutter/material.dart';

import '../../core/focus.dart';
import '../../core/theme.dart';
import '../../data/store/watch_progress.dart';
import 'poster_card.dart';

/// Continue Watching row: poster cards with a watched-progress bar, paginated
/// in pages of [_pageSize] via a trailing "More" card. Mirrors the Kotlin
/// `ContinueWatchingRow`.
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
  int _visible = _pageSize;

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final shown = _visible.clamp(0, total);
    final hasMore = shown < total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 40, bottom: 10),
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
          height: 248,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Don't clip the focus scale-up of the cards.
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
            itemCount: shown + (hasMore ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              if (index >= shown) {
                return _MoreCard(
                  onTap: () => setState(() => _visible += _pageSize),
                );
              }
              final p = widget.items[index];
              return _ContinueWatchingCard(
                progress: p,
                autofocus: index == 0 && widget.autofocusFirst,
                focusNode: index == 0 ? widget.firstItemFocusNode : null,
                onFocusChange: (f) {
                  if (f) widget.onFocus?.call(p);
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
    final isTv = progress.type == 'tv';
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FocusableCard(
            onTap: onTap,
            autofocus: autofocus,
            focusNode: focusNode,
            onFocusChange: onFocusChange,
            focusedScale: 1.08,
            borderWidth: 3,
            borderRadius: BorderRadius.circular(6),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(
                    path: progress.posterPath,
                    title: progress.title ?? '',
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
          const SizedBox(height: 6),
          Text(
            progress.title ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
            ),
          ),
          if (isTv)
            Text(
              'S${progress.season ?? 1} · E${progress.episode ?? 1}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}

class _MoreCard extends StatelessWidget {
  const _MoreCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: FocusableCard(
        onTap: onTap,
        focusedScale: 1.08,
        borderRadius: BorderRadius.circular(6),
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: Container(
            color: AppColors.charcoalLight,
            alignment: Alignment.center,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_right, color: AppColors.textPrimary, size: 32),
                SizedBox(height: 4),
                Text('More', style: TextStyle(color: AppColors.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/media_details.dart';
import '../../data/models/media_item.dart';
import 'continue_watching_row.dart';
import 'poster_card.dart';

/// A titled row of poster cards. See more keeps the row one line tall and
/// slides five titles at a time.
class CategoryRowSection extends StatefulWidget {
  const CategoryRowSection({
    super.key,
    required this.row,
    required this.onItemTap,
    this.onItemFocus,
    this.firstItemFocusNode,
    this.autofocusFirst = false,
  });

  final CategoryRow row;
  final void Function(MediaItem item) onItemTap;
  final void Function(MediaItem item)? onItemFocus;
  final FocusNode? firstItemFocusNode;
  final bool autofocusFirst;

  @override
  State<CategoryRowSection> createState() => _CategoryRowSectionState();
}

class _CategoryRowSectionState extends State<CategoryRowSection> {
  // When a card in this row gains focus, scroll the whole section (title + row)
  // into view vertically so the title is never clipped and the row snaps near
  // the top of the list — this is what makes D-pad up/down navigation land
  // predictably on TV. Uses the section's own context, which sits in the outer
  // vertical list only, so horizontal scrolling of the row is untouched.
  void _ensureSectionVisible() {
    // Runs shortly after the framework's own directional-focus scroll (which
    // otherwise pins the card to the viewport edge and clips this row's title),
    // so our section-level alignment — which keeps the title in view and snaps
    // the row near the top — is the one that sticks.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 40, bottom: 6),
          child: Text(
            widget.row.title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: PagedPosterGrid(
            rows: 1,
            itemCount: widget.row.items.length,
            firstItemFocusNode: widget.firstItemFocusNode,
            posterPath: (i) => widget.row.items[i].posterPath,
            itemBuilder: (context, index, lead, focusNode) {
              final item = widget.row.items[index];
              return FittedBox(
                fit: BoxFit.contain,
                child: PosterCard(
                  item: item,
                  width: 132,
                  watchedType: widget.row.fallbackType,
                  autofocus: lead && widget.autofocusFirst,
                  focusNode: focusNode,
                  ensureVisibleOnFocus: true,
                  onFocusChange: (f) {
                    if (f) {
                      widget.onItemFocus?.call(item);
                      _ensureSectionVisible();
                    }
                  },
                  onTap: () => widget.onItemTap(item),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

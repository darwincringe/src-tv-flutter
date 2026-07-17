import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/media_details.dart';
import '../../data/models/media_item.dart';
import 'poster_card.dart';

/// A titled horizontal row of poster cards. Mirrors the Kotlin
/// `CategoryRowSection`.
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
          padding: const EdgeInsets.only(left: 40, bottom: 10),
          child: Text(
            widget.row.title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Don't clip the focus scale-up of the poster cards.
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
            itemCount: widget.row.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final item = widget.row.items[index];
              return PosterCard(
                item: item,
                autofocus: index == 0 && widget.autofocusFirst,
                focusNode: index == 0 ? widget.firstItemFocusNode : null,
                onFocusChange: (f) {
                  if (f) {
                    widget.onItemFocus?.call(item);
                    _ensureSectionVisible();
                  }
                },
                onTap: () => widget.onItemTap(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

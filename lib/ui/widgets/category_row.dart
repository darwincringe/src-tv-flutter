import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/media_details.dart';
import '../../data/models/media_item.dart';
import 'poster_card.dart';

/// A titled horizontal row of poster cards. Mirrors the Kotlin
/// `CategoryRowSection`.
class CategoryRowSection extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 40, bottom: 10),
          child: Text(
            row.title,
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
            itemCount: row.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final item = row.items[index];
              return PosterCard(
                item: item,
                autofocus: index == 0 && autofocusFirst,
                focusNode: index == 0 ? firstItemFocusNode : null,
                onFocusChange: (f) {
                  if (f) onItemFocus?.call(item);
                },
                onTap: () => onItemTap(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

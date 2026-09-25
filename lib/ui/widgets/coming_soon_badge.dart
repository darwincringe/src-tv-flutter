import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A small amber "COMING SOON" pill for upcoming / brand-new titles. Purely
/// informational — the Play button stays enabled. Used on the details page and
/// the hero; [PosterComingSoonBadge] overlays it on a poster card.
class ComingSoonBadge extends StatelessWidget {
  const ComingSoonBadge({super.key, this.big = false});
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: big ? 10 : 7,
        vertical: big ? 5 : 3,
      ),
      decoration: BoxDecoration(
        color: AppColors.ratingYellow,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Text(
        'COMING SOON',
        style: TextStyle(
          color: AppColors.charcoal,
          fontSize: big ? 12 : 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// The [ComingSoonBadge] positioned in the top-right corner of a poster tile.
class PosterComingSoonBadge extends StatelessWidget {
  const PosterComingSoonBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      top: 6,
      right: 6,
      child: ComingSoonBadge(),
    );
  }
}

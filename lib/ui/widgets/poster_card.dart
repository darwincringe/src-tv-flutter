import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/focus.dart';
import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import '../../data/tmdb/image_urls.dart';
import 'coming_soon_badge.dart';

/// A 2:3 poster tile used across the category rows. Focus scales it up and
/// draws a white border (matching the Kotlin `PosterCard`).
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onFocusChange,
    this.autofocus = false,
    this.focusNode,
    this.width = 114,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;
  final FocusNode? focusNode;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: FocusableCard(
        onTap: onTap,
        autofocus: autofocus,
        focusNode: focusNode,
        onFocusChange: onFocusChange,
        focusedScale: 1.08,
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PosterImage(
                path: item.posterPath,
                title: item.displayTitle,
                displayWidth: width,
              ),
              if (item.comingSoon) const PosterComingSoonBadge(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A poster image with a graceful placeholder for missing/broken art.
///
/// [displayWidth] is the logical width the poster is shown at; the image is
/// decoded to roughly that many physical pixels (memCacheWidth) instead of the
/// full source resolution, which cuts decoded RAM dramatically on a TV.
class PosterImage extends StatelessWidget {
  const PosterImage({
    super.key,
    required this.path,
    required this.title,
    this.displayWidth = 130,
  });
  final String? path;
  final String title;
  final double displayWidth;

  @override
  Widget build(BuildContext context) {
    final url = posterUrl(path);
    if (url == null) return _placeholder();
    final cacheWidth =
        (displayWidth * MediaQuery.devicePixelRatioOf(context)).round().clamp(120, 342);
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: cacheWidth,
      // Smooth cross-fade up from black (instead of a hard "box" pop-in).
      fadeInDuration: const Duration(milliseconds: 400),
      fadeInCurve: Curves.easeOut,
      fadeOutDuration: const Duration(milliseconds: 250),
      placeholder: (_, _) => const ColoredBox(color: Colors.black),
      errorWidget: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.charcoalLight,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: Text(
          title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      );
}

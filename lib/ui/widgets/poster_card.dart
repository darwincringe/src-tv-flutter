import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/focus.dart';
import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import '../../data/tmdb/image_urls.dart';

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
        borderRadius: BorderRadius.circular(6),
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: PosterImage(path: item.posterPath, title: item.displayTitle),
        ),
      ),
    );
  }
}

/// A poster image with a graceful placeholder for missing/broken art.
class PosterImage extends StatelessWidget {
  const PosterImage({super.key, required this.path, required this.title});
  final String? path;
  final String title;

  @override
  Widget build(BuildContext context) {
    final url = posterUrl(path);
    if (url == null) return _placeholder();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, _) => Container(color: AppColors.charcoalLight),
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

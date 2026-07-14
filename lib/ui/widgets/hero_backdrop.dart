import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/language.dart';
import '../../data/models/media_item.dart';
import '../../data/tmdb/image_urls.dart';

/// The hero backdrop image with charcoal fades, pinned top-right and fading
/// into the page. Follows D-pad focus (the parent updates [item]). Mirrors the
/// Kotlin `HeroBackdrop`.
class HeroBackdrop extends StatelessWidget {
  const HeroBackdrop({super.key, required this.item});
  final MediaItem? item;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final url = backdropUrl(item?.backdropPath);
        return Stack(
          children: [
            if (url != null)
              Positioned(
                top: 0,
                right: 0,
                width: constraints.maxWidth * 0.80,
                height: constraints.maxHeight * 0.72,
                child: CachedNetworkImage(
                  key: ValueKey(item!.backdropPath),
                  imageUrl: url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  fadeInDuration: const Duration(milliseconds: 250),
                ),
              ),
            // Horizontal fade: Charcoal on the left → transparent, so the
            // image's left edge dissolves behind the title/description.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [AppColors.charcoal, Color(0x00161616)],
                    stops: [0.30, 0.62],
                  ),
                ),
              ),
            ),
            // Vertical fade: transparent → Charcoal so the image's bottom edge
            // dissolves into the rows below.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00161616), AppColors.charcoal],
                    stops: [0.42, 0.72],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The title/language/overview overlay for the hero. Full-width in portrait,
/// ~48% width otherwise. Mirrors the Kotlin `HeroInfo`.
class HeroInfo extends StatelessWidget {
  const HeroInfo({super.key, required this.item, required this.portrait});
  final MediaItem? item;
  final bool portrait;

  @override
  Widget build(BuildContext context) {
    final it = item;
    if (it == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(left: 40, top: 40, right: portrait ? 40 : 0),
      child: Align(
        alignment: Alignment.topLeft,
        child: FractionallySizedBox(
          widthFactor: portrait ? 1 : 0.48,
          alignment: Alignment.topLeft,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                it.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Language : ${languageName(it.originalLanguage)}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                it.overview ?? '',
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

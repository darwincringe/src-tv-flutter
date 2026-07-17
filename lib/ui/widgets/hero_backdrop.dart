import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/language.dart';
import '../../data/models/media_details.dart';
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
                  // Decode to ~display width, not the full w1280 (~3.7 MB each);
                  // the hero swaps on every focus hop so this matters a lot.
                  memCacheWidth:
                      (constraints.maxWidth * 0.80 * MediaQuery.devicePixelRatioOf(context))
                          .round()
                          .clamp(320, 1280),
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

/// The hero title + metadata + overview overlay. Full-width in portrait, ~48%
/// otherwise. [details] (loaded lazily on focus) enriches it with the same
/// year · rating · runtime · language · genres shown on the details page.
class HeroInfo extends StatelessWidget {
  const HeroInfo({
    super.key,
    required this.item,
    required this.portrait,
    this.details,
  });
  final MediaItem? item;
  final bool portrait;
  final MediaDetails? details;

  static String _fmtRuntime(int m) {
    final h = m ~/ 60;
    final mm = m % 60;
    return h > 0 ? '${h}h ${mm}m' : '${mm}m';
  }

  @override
  Widget build(BuildContext context) {
    final it = item;
    if (it == null) return const SizedBox.shrink();
    final d = details;

    final year = d?.year ?? it.year;
    final rating = d?.rating ?? it.voteAverage ?? 0;
    final runtime = d?.runtimeMinutes;
    final language = d?.language ?? languageName(it.originalLanguage);
    final meta = <String>[
      if (year != null && year.isNotEmpty) year,
      if (rating > 0) '★ ${rating.toStringAsFixed(1)}',
      if (runtime != null && runtime > 0) _fmtRuntime(runtime),
      if (language.isNotEmpty && language.toLowerCase() != 'unknown') language,
    ];
    final genres = d?.genres ?? const <String>[];

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
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  meta.join('  ·  '),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
              if (genres.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  genres.join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
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

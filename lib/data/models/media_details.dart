import 'credits.dart';
import 'details_dto.dart';
import 'media_item.dart';

/// Unified details model consumed by the UI, built from either a
/// [MovieDetailsDto] or [TvDetailsDto]. Mirrors the Kotlin `MediaDetails`.
class MediaDetails {
  final int id;
  final bool isTv;
  final String title;
  final String? tagline;
  final String overview;
  final String? backdropPath;
  final String? posterPath;
  final String? year;
  final double rating;
  final int? runtimeMinutes;
  final String? language;
  final List<String> genres;
  final List<CastMember> cast;
  final String? trailerKey;
  final int numberOfSeasons;
  final List<Season> seasons;
  /// Full release / first-air date ("2026-08-01").
  final String? releaseDate;

  /// "Coming Soon" for a movie means it is in theaters (or about to be) and
  /// not on a streaming service yet. For TV, the series has not premiered.
  /// Purely informational — Play stays enabled.
  final bool comingSoon;

  const MediaDetails({
    required this.id,
    required this.isTv,
    required this.title,
    this.tagline,
    required this.overview,
    this.backdropPath,
    this.posterPath,
    this.year,
    required this.rating,
    this.runtimeMinutes,
    this.language,
    this.genres = const [],
    this.cast = const [],
    this.trailerKey,
    this.numberOfSeasons = 0,
    this.seasons = const [],
    this.releaseDate,
    this.comingSoon = false,
  });
}

/// A titled horizontal row of [MediaItem]s. `fallbackType` is used when an
/// item has no `media_type` of its own (e.g. discover/movie results).
class CategoryRow {
  final String title;
  final String fallbackType;
  final List<MediaItem> items;

  const CategoryRow({
    required this.title,
    required this.fallbackType,
    required this.items,
  });
}

/// A category whose titles are fetched the first time the row is on screen.
class CategorySource {
  CategorySource({
    required this.title,
    required this.fallbackType,
    required this.load,
  });

  final String title;
  final String fallbackType;
  final Future<List<MediaItem>> Function() load;
  Future<List<MediaItem>>? _pending;

  Future<List<MediaItem>> fetch() => _pending ??= load();
}

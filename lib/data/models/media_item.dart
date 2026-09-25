import 'package:json_annotation/json_annotation.dart';

import '../../core/dates.dart';

part 'media_item.g.dart';

/// A movie or TV entry as returned by TMDB list/search endpoints.
///
/// Mirrors the Kotlin `MediaItem` DTO (snake_case JSON) plus its computed
/// helpers (`displayTitle`, `year`, `resolvedType`).
@JsonSerializable(fieldRename: FieldRename.snake)
class MediaItem {
  final int id;
  final String? mediaType;
  final String? title;
  final String? name;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final String? firstAirDate;
  final double? voteAverage;
  final String? originalLanguage;

  const MediaItem({
    required this.id,
    this.mediaType,
    this.title,
    this.name,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.firstAirDate,
    this.voteAverage,
    this.originalLanguage,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) =>
      _$MediaItemFromJson(json);

  Map<String, dynamic> toJson() => _$MediaItemToJson(this);

  /// Returns a copy, optionally tagging the [mediaType] (used to label
  /// discover/* results, which don't carry a media_type of their own).
  MediaItem copyWith({String? mediaType}) => MediaItem(
        id: id,
        mediaType: mediaType ?? this.mediaType,
        title: title,
        name: name,
        overview: overview,
        posterPath: posterPath,
        backdropPath: backdropPath,
        releaseDate: releaseDate,
        firstAirDate: firstAirDate,
        voteAverage: voteAverage,
        originalLanguage: originalLanguage,
      );

  /// Prefer movie `title`, fall back to TV `name`.
  String get displayTitle => title ?? name ?? '';

  /// First 4 chars of the release/air date (the year), or null.
  String? get year {
    final date = releaseDate ?? firstAirDate;
    if (date == null || date.length < 4) return null;
    return date.substring(0, 4);
  }

  /// Returns `media_type` when it is a real type, otherwise [fallback].
  String resolvedType(String fallback) {
    if (mediaType == 'movie' || mediaType == 'tv') return mediaType!;
    return fallback;
  }

  /// Whether to badge this as "Coming Soon". Movies: upcoming or released
  /// within the last 30 days. TV: first air date still in the future.
  bool get comingSoon => resolvedType('movie') == 'tv'
      ? isComingSoon(firstAirDate)
      : isComingSoonRelease(releaseDate);
}

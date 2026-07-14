import 'package:json_annotation/json_annotation.dart';

import 'credits.dart';
import 'genre.dart';
import 'videos.dart';

part 'details_dto.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class MovieDetailsDto {
  final int id;
  final String? title;
  final String? overview;
  final String? tagline;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final int? runtime;
  final double? voteAverage;
  final String? originalLanguage;
  @JsonKey(defaultValue: [])
  final List<Genre> genres;
  final CreditsDto? credits;
  final VideosDto? videos;

  const MovieDetailsDto({
    required this.id,
    this.title,
    this.overview,
    this.tagline,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.runtime,
    this.voteAverage,
    this.originalLanguage,
    this.genres = const [],
    this.credits,
    this.videos,
  });

  factory MovieDetailsDto.fromJson(Map<String, dynamic> json) =>
      _$MovieDetailsDtoFromJson(json);

  Map<String, dynamic> toJson() => _$MovieDetailsDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class TvDetailsDto {
  final int id;
  final String? name;
  final String? overview;
  final String? tagline;
  final String? posterPath;
  final String? backdropPath;
  final String? firstAirDate;
  @JsonKey(defaultValue: [])
  final List<int> episodeRunTime;
  final double? voteAverage;
  final String? originalLanguage;
  final int? numberOfSeasons;
  @JsonKey(defaultValue: [])
  final List<Genre> genres;
  @JsonKey(defaultValue: [])
  final List<Season> seasons;
  final CreditsDto? credits;
  final VideosDto? videos;

  const TvDetailsDto({
    required this.id,
    this.name,
    this.overview,
    this.tagline,
    this.posterPath,
    this.backdropPath,
    this.firstAirDate,
    this.episodeRunTime = const [],
    this.voteAverage,
    this.originalLanguage,
    this.numberOfSeasons,
    this.genres = const [],
    this.seasons = const [],
    this.credits,
    this.videos,
  });

  factory TvDetailsDto.fromJson(Map<String, dynamic> json) =>
      _$TvDetailsDtoFromJson(json);

  Map<String, dynamic> toJson() => _$TvDetailsDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class Season {
  final int id;
  final int seasonNumber;
  final String? name;
  final int? episodeCount;
  final String? posterPath;

  const Season({
    required this.id,
    required this.seasonNumber,
    this.name,
    this.episodeCount,
    this.posterPath,
  });

  factory Season.fromJson(Map<String, dynamic> json) => _$SeasonFromJson(json);

  Map<String, dynamic> toJson() => _$SeasonToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class SeasonDetailsDto {
  @JsonKey(defaultValue: [])
  final List<Episode> episodes;

  const SeasonDetailsDto({this.episodes = const []});

  factory SeasonDetailsDto.fromJson(Map<String, dynamic> json) =>
      _$SeasonDetailsDtoFromJson(json);

  Map<String, dynamic> toJson() => _$SeasonDetailsDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class Episode {
  final int id;
  final int episodeNumber;
  final String? name;
  final String? overview;
  final String? stillPath;
  final int? runtime;
  final String? airDate;
  final double? voteAverage;

  const Episode({
    required this.id,
    required this.episodeNumber,
    this.name,
    this.overview,
    this.stillPath,
    this.runtime,
    this.airDate,
    this.voteAverage,
  });

  factory Episode.fromJson(Map<String, dynamic> json) =>
      _$EpisodeFromJson(json);

  Map<String, dynamic> toJson() => _$EpisodeToJson(this);
}

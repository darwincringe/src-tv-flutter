// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'details_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MovieDetailsDto _$MovieDetailsDtoFromJson(Map<String, dynamic> json) =>
    MovieDetailsDto(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String?,
      overview: json['overview'] as String?,
      tagline: json['tagline'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate: json['release_date'] as String?,
      runtime: (json['runtime'] as num?)?.toInt(),
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      originalLanguage: json['original_language'] as String?,
      genres:
          (json['genres'] as List<dynamic>?)
              ?.map((e) => Genre.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      credits: json['credits'] == null
          ? null
          : CreditsDto.fromJson(json['credits'] as Map<String, dynamic>),
      videos: json['videos'] == null
          ? null
          : VideosDto.fromJson(json['videos'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$MovieDetailsDtoToJson(MovieDetailsDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'overview': instance.overview,
      'tagline': instance.tagline,
      'poster_path': instance.posterPath,
      'backdrop_path': instance.backdropPath,
      'release_date': instance.releaseDate,
      'runtime': instance.runtime,
      'vote_average': instance.voteAverage,
      'original_language': instance.originalLanguage,
      'genres': instance.genres,
      'credits': instance.credits,
      'videos': instance.videos,
    };

TvDetailsDto _$TvDetailsDtoFromJson(Map<String, dynamic> json) => TvDetailsDto(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String?,
  overview: json['overview'] as String?,
  tagline: json['tagline'] as String?,
  posterPath: json['poster_path'] as String?,
  backdropPath: json['backdrop_path'] as String?,
  firstAirDate: json['first_air_date'] as String?,
  episodeRunTime:
      (json['episode_run_time'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList() ??
      [],
  voteAverage: (json['vote_average'] as num?)?.toDouble(),
  originalLanguage: json['original_language'] as String?,
  numberOfSeasons: (json['number_of_seasons'] as num?)?.toInt(),
  genres:
      (json['genres'] as List<dynamic>?)
          ?.map((e) => Genre.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  seasons:
      (json['seasons'] as List<dynamic>?)
          ?.map((e) => Season.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  credits: json['credits'] == null
      ? null
      : CreditsDto.fromJson(json['credits'] as Map<String, dynamic>),
  videos: json['videos'] == null
      ? null
      : VideosDto.fromJson(json['videos'] as Map<String, dynamic>),
);

Map<String, dynamic> _$TvDetailsDtoToJson(TvDetailsDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'overview': instance.overview,
      'tagline': instance.tagline,
      'poster_path': instance.posterPath,
      'backdrop_path': instance.backdropPath,
      'first_air_date': instance.firstAirDate,
      'episode_run_time': instance.episodeRunTime,
      'vote_average': instance.voteAverage,
      'original_language': instance.originalLanguage,
      'number_of_seasons': instance.numberOfSeasons,
      'genres': instance.genres,
      'seasons': instance.seasons,
      'credits': instance.credits,
      'videos': instance.videos,
    };

Season _$SeasonFromJson(Map<String, dynamic> json) => Season(
  id: (json['id'] as num).toInt(),
  seasonNumber: (json['season_number'] as num).toInt(),
  name: json['name'] as String?,
  episodeCount: (json['episode_count'] as num?)?.toInt(),
  posterPath: json['poster_path'] as String?,
);

Map<String, dynamic> _$SeasonToJson(Season instance) => <String, dynamic>{
  'id': instance.id,
  'season_number': instance.seasonNumber,
  'name': instance.name,
  'episode_count': instance.episodeCount,
  'poster_path': instance.posterPath,
};

SeasonDetailsDto _$SeasonDetailsDtoFromJson(Map<String, dynamic> json) =>
    SeasonDetailsDto(
      episodes:
          (json['episodes'] as List<dynamic>?)
              ?.map((e) => Episode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$SeasonDetailsDtoToJson(SeasonDetailsDto instance) =>
    <String, dynamic>{'episodes': instance.episodes};

Episode _$EpisodeFromJson(Map<String, dynamic> json) => Episode(
  id: (json['id'] as num).toInt(),
  episodeNumber: (json['episode_number'] as num).toInt(),
  name: json['name'] as String?,
  overview: json['overview'] as String?,
  stillPath: json['still_path'] as String?,
  runtime: (json['runtime'] as num?)?.toInt(),
  airDate: json['air_date'] as String?,
  voteAverage: (json['vote_average'] as num?)?.toDouble(),
);

Map<String, dynamic> _$EpisodeToJson(Episode instance) => <String, dynamic>{
  'id': instance.id,
  'episode_number': instance.episodeNumber,
  'name': instance.name,
  'overview': instance.overview,
  'still_path': instance.stillPath,
  'runtime': instance.runtime,
  'air_date': instance.airDate,
  'vote_average': instance.voteAverage,
};

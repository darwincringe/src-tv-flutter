// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MediaItem _$MediaItemFromJson(Map<String, dynamic> json) => MediaItem(
  id: (json['id'] as num).toInt(),
  mediaType: json['media_type'] as String?,
  title: json['title'] as String?,
  name: json['name'] as String?,
  overview: json['overview'] as String?,
  posterPath: json['poster_path'] as String?,
  backdropPath: json['backdrop_path'] as String?,
  releaseDate: json['release_date'] as String?,
  firstAirDate: json['first_air_date'] as String?,
  voteAverage: (json['vote_average'] as num?)?.toDouble(),
  originalLanguage: json['original_language'] as String?,
);

Map<String, dynamic> _$MediaItemToJson(MediaItem instance) => <String, dynamic>{
  'id': instance.id,
  'media_type': instance.mediaType,
  'title': instance.title,
  'name': instance.name,
  'overview': instance.overview,
  'poster_path': instance.posterPath,
  'backdrop_path': instance.backdropPath,
  'release_date': instance.releaseDate,
  'first_air_date': instance.firstAirDate,
  'vote_average': instance.voteAverage,
  'original_language': instance.originalLanguage,
};

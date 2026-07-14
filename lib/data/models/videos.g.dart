// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'videos.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VideosDto _$VideosDtoFromJson(Map<String, dynamic> json) => VideosDto(
  results:
      (json['results'] as List<dynamic>?)
          ?.map((e) => VideoDto.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);

Map<String, dynamic> _$VideosDtoToJson(VideosDto instance) => <String, dynamic>{
  'results': instance.results,
};

VideoDto _$VideoDtoFromJson(Map<String, dynamic> json) => VideoDto(
  key: json['key'] as String?,
  site: json['site'] as String?,
  type: json['type'] as String?,
  official: json['official'] as bool?,
);

Map<String, dynamic> _$VideoDtoToJson(VideoDto instance) => <String, dynamic>{
  'key': instance.key,
  'site': instance.site,
  'type': instance.type,
  'official': instance.official,
};

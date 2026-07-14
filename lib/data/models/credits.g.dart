// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credits.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreditsDto _$CreditsDtoFromJson(Map<String, dynamic> json) => CreditsDto(
  cast:
      (json['cast'] as List<dynamic>?)
          ?.map((e) => CastMember.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);

Map<String, dynamic> _$CreditsDtoToJson(CreditsDto instance) =>
    <String, dynamic>{'cast': instance.cast};

CastMember _$CastMemberFromJson(Map<String, dynamic> json) => CastMember(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String?,
  character: json['character'] as String?,
  profilePath: json['profile_path'] as String?,
);

Map<String, dynamic> _$CastMemberToJson(CastMember instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'character': instance.character,
      'profile_path': instance.profilePath,
    };

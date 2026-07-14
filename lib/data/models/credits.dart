import 'package:json_annotation/json_annotation.dart';

part 'credits.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class CreditsDto {
  @JsonKey(defaultValue: [])
  final List<CastMember> cast;

  const CreditsDto({this.cast = const []});

  factory CreditsDto.fromJson(Map<String, dynamic> json) =>
      _$CreditsDtoFromJson(json);

  Map<String, dynamic> toJson() => _$CreditsDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class CastMember {
  final int id;
  final String? name;
  final String? character;
  final String? profilePath;

  const CastMember({
    required this.id,
    this.name,
    this.character,
    this.profilePath,
  });

  factory CastMember.fromJson(Map<String, dynamic> json) =>
      _$CastMemberFromJson(json);

  Map<String, dynamic> toJson() => _$CastMemberToJson(this);
}

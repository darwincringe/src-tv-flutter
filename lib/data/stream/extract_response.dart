import 'package:json_annotation/json_annotation.dart';

part 'extract_response.g.dart';

/// Response from the self-hosted extract backend
/// `GET /extract?tmdb_id=&type=&season=&episode=`.
@JsonSerializable(fieldRename: FieldRename.snake)
class ExtractResponse {
  final bool success;
  final String? hlsUrl;
  @JsonKey(defaultValue: [])
  final List<String> subtitles;
  final String? error;

  const ExtractResponse({
    this.success = false,
    this.hlsUrl,
    this.subtitles = const [],
    this.error,
  });

  factory ExtractResponse.fromJson(Map<String, dynamic> json) =>
      _$ExtractResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ExtractResponseToJson(this);
}

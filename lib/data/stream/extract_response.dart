import 'package:json_annotation/json_annotation.dart';

part 'extract_response.g.dart';

/// One playable mirror from `GET /extract`. [source] is stored for the user's
/// preference and is never shown in the player — the button label is only
/// "Source N" plus [quality].
class StreamMirror {
  final String hlsUrl;
  final String source;
  final String quality;

  const StreamMirror({
    required this.hlsUrl,
    required this.source,
    this.quality = '',
  });
}

/// Response from the self-hosted extract backend
/// `GET /extract?tmdb_id=&type=&season=&episode=&source=`.
@JsonSerializable(fieldRename: FieldRename.snake)
class ExtractResponse {
  final bool success;
  final String? hlsUrl;
  @JsonKey(defaultValue: [])
  final List<String> subtitles;
  final String? error;

  /// Every mirror the backend can play. Empty on older responses that only
  /// send [hlsUrl].
  final List<StreamMirror> mirrors;

  const ExtractResponse({
    this.success = false,
    this.hlsUrl,
    this.subtitles = const [],
    this.error,
    this.mirrors = const [],
  });

  factory ExtractResponse.fromJson(Map<String, dynamic> json) =>
      _$ExtractResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ExtractResponseToJson(this);
}

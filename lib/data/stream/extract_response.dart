import 'package:json_annotation/json_annotation.dart';

part 'extract_response.g.dart';

/// One playable mirror from `GET /extract`. [source] is the provider name
/// shown on the player button, together with [quality].
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

/// Response from `GET /extract/vaplayer` or `GET /wyzie`.
@JsonSerializable(fieldRename: FieldRename.snake)
class ExtractResponse {
  final bool success;
  final String? hlsUrl;
  @JsonKey(defaultValue: [])
  final List<String> subtitles;
  final String? error;

  /// Provider and quality of the top-level [hlsUrl]. Not part of the generated
  /// JSON helper; the client fills them in while parsing.
  final String? source;
  final String? quality;

  /// Mirrors from this one response. Empty when the body only sends [hlsUrl].
  final List<StreamMirror> mirrors;

  const ExtractResponse({
    this.success = false,
    this.hlsUrl,
    this.subtitles = const [],
    this.error,
    this.source,
    this.quality,
    this.mirrors = const [],
  });

  factory ExtractResponse.fromJson(Map<String, dynamic> json) =>
      _$ExtractResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ExtractResponseToJson(this);
}

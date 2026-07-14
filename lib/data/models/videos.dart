import 'package:json_annotation/json_annotation.dart';

part 'videos.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class VideosDto {
  @JsonKey(defaultValue: [])
  final List<VideoDto> results;

  const VideosDto({this.results = const []});

  factory VideosDto.fromJson(Map<String, dynamic> json) =>
      _$VideosDtoFromJson(json);

  Map<String, dynamic> toJson() => _$VideosDtoToJson(this);

  /// Best YouTube trailer key: official Trailer → Trailer → Teaser → first.
  /// Mirrors the Kotlin `bestTrailerKey()`.
  String? bestTrailerKey() {
    final youtube = results.where((v) => v.isYouTube).toList();
    if (youtube.isEmpty) return null;

    VideoDto? pick(bool Function(VideoDto) test) {
      for (final v in youtube) {
        if (test(v)) return v;
      }
      return null;
    }

    final chosen = pick((v) => v.type == 'Trailer' && v.official == true) ??
        pick((v) => v.type == 'Trailer') ??
        pick((v) => v.type == 'Teaser') ??
        youtube.first;
    return chosen.key;
  }
}

@JsonSerializable(fieldRename: FieldRename.snake)
class VideoDto {
  final String? key;
  final String? site;
  final String? type;
  final bool? official;

  const VideoDto({this.key, this.site, this.type, this.official});

  factory VideoDto.fromJson(Map<String, dynamic> json) =>
      _$VideoDtoFromJson(json);

  Map<String, dynamic> toJson() => _$VideoDtoToJson(this);

  bool get isYouTube => site == 'YouTube' && (key?.isNotEmpty ?? false);
}

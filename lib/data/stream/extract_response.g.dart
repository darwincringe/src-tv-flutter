// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'extract_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ExtractResponse _$ExtractResponseFromJson(Map<String, dynamic> json) =>
    ExtractResponse(
      success: json['success'] as bool? ?? false,
      hlsUrl: json['hls_url'] as String?,
      subtitles:
          (json['subtitles'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      error: json['error'] as String?,
    );

Map<String, dynamic> _$ExtractResponseToJson(ExtractResponse instance) =>
    <String, dynamic>{
      'success': instance.success,
      'hls_url': instance.hlsUrl,
      'subtitles': instance.subtitles,
      'error': instance.error,
    };

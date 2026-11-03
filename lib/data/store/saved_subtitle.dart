import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The SRT the viewer picked from search, kept on this device.
class SavedSubtitle {
  final String fileId;
  final String label;
  final String? language;
  final String body;

  const SavedSubtitle({
    required this.fileId,
    required this.label,
    required this.body,
    this.language,
  });
}

/// One searched subtitle per movie, or per TV episode. Not synced: the file
/// stays on this device so the next visit does not search again.
class SavedSubtitleStore {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String _key(
    String type,
    int tmdbId,
    int? season,
    int? episode,
  ) =>
      type == 'tv'
          ? 'savedsub_tv-$tmdbId-s${season ?? 0}e${episode ?? 0}'
          : 'savedsub_movie-$tmdbId';

  static Future<void> save(
    String type,
    int tmdbId,
    int? season,
    int? episode,
    SavedSubtitle subtitle,
  ) async {
    await _prefs.setString(
      _key(type, tmdbId, season, episode),
      jsonEncode({
        'fileId': subtitle.fileId,
        'label': subtitle.label,
        'language': subtitle.language,
        'body': subtitle.body,
      }),
    );
  }

  static SavedSubtitle? get(
    String type,
    int tmdbId,
    int? season,
    int? episode,
  ) {
    final raw = _prefs.getString(_key(type, tmdbId, season, episode));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final body = decoded['body'];
      final fileId = decoded['fileId'];
      final label = decoded['label'];
      if (body is! String || body.trim().isEmpty) return null;
      if (fileId is! String || fileId.isEmpty) return null;
      final language = decoded['language'];
      return SavedSubtitle(
        fileId: fileId,
        label: label is String && label.trim().isNotEmpty ? label : 'Subtitle',
        language: language is String && language.isNotEmpty ? language : null,
        body: body,
      );
    } catch (_) {
      return null;
    }
  }
}

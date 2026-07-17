import '../../data/models/language.dart';

/// A selectable external subtitle track. Mirrors the config built by the Kotlin
/// `SubtitleConfigs.kt`.
class SubtitleOption {
  final String uri;
  final String label;
  final String? language;

  const SubtitleOption({
    required this.uri,
    required this.label,
    this.language,
  });
}

/// filename keyword → ISO code. Mirrors `detectLanguage` (17 languages).
const Map<String, String> _langKeywords = {
  'english': 'en',
  'spanish': 'es',
  'french': 'fr',
  'german': 'de',
  'italian': 'it',
  'portuguese': 'pt',
  'brazilian': 'pt',
  'dutch': 'nl',
  'turkish': 'tr',
  'russian': 'ru',
  'japanese': 'ja',
  'korean': 'ko',
  'chinese': 'zh',
  'hindi': 'hi',
  'arabic': 'ar',
  'thai': 'th',
  'tagalog': 'tl',
  'filipino': 'tl',
  'indonesian': 'id',
  'vietnamese': 'vi',
};

String? detectLanguage(String source) {
  final lower = source.toLowerCase();
  for (final entry in _langKeywords.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }
  return null;
}

/// Builds a subtitle option from an extract-API subtitle URL. Two shapes show
/// up in the backend's subtitle list (mirrors the Kotlin `apiSubtitleConfig`):
///  - our proxy with a real query string:
///    `.../movie-subtitle-srt?url=...english-yify.zip&release=WEBRIP`
///  - raw source links with NO leading `?`, e.g.
///    `dl.opensubtitles.org/.../file/1955789523&release=ENGLISH.BLURAY`.
///    Here `&release=...` is NOT a query param, so it must be split off by hand
///    — otherwise it gets sent as part of the file path and the request 404s
///    (this is why some subtitles silently failed to load).
///
/// The visible label prefers `release`, then the detected language display
/// name, then "Subtitle". Language is detected from the inner filename/release.
SubtitleOption apiSubtitleOption(String url) {
  String? release;
  String inner;
  String requestUrl;
  if (url.contains('?')) {
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {}
    release = uri?.queryParameters['release']?.trim();
    inner = uri?.queryParameters['url'] ?? url;
    requestUrl = url;
  } else {
    final match =
        RegExp(r'&release=(.+)$', caseSensitive: false).firstMatch(url);
    release = match != null ? Uri.decodeFull(match.group(1)!).trim() : null;
    requestUrl = match != null ? url.substring(0, match.start) : url;
    inner = requestUrl;
  }

  final language = detectLanguage('$inner ${release ?? ''}');
  final String label;
  if (release != null && release.isNotEmpty) {
    label = release;
  } else if (language != null) {
    label = languageName(language);
  } else {
    label = 'Subtitle';
  }
  return SubtitleOption(uri: requestUrl, label: label, language: language);
}

List<SubtitleOption> apiSubtitleOptions(List<String> urls) =>
    urls.map(apiSubtitleOption).toList();

/// Label for an uploaded subtitle file.
SubtitleOption uploadedSubtitleOption(String uri, int index) => SubtitleOption(
      uri: uri,
      label: index == 0 ? 'Uploaded' : 'Uploaded ${index + 1}',
    );

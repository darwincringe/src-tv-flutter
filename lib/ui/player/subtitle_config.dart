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

/// Builds a subtitle option from an extract-API subtitle URL. The visible
/// label prefers the `release=` query param (e.g. WEBRIP), then the detected
/// language display name, then "Subtitle". Language is detected from the inner
/// `url=` param (the original subtitle filename).
SubtitleOption apiSubtitleOption(String url) {
  String? release;
  String? inner;
  try {
    final uri = Uri.parse(url);
    release = uri.queryParameters['release'];
    inner = uri.queryParameters['url'];
  } catch (_) {}

  final language = detectLanguage(inner ?? url);
  final String label;
  if (release != null && release.isNotEmpty) {
    label = release;
  } else if (language != null) {
    label = languageName(language);
  } else {
    label = 'Subtitle';
  }
  return SubtitleOption(uri: url, label: label, language: language);
}

List<SubtitleOption> apiSubtitleOptions(List<String> urls) =>
    urls.map(apiSubtitleOption).toList();

/// Label for an uploaded subtitle file.
SubtitleOption uploadedSubtitleOption(String uri, int index) => SubtitleOption(
      uri: uri,
      label: index == 0 ? 'Uploaded' : 'Uploaded ${index + 1}',
    );

/// ISO-639-1 code → English display name. Mirrors the Kotlin `languageName`.
const Map<String, String> _languageNames = {
  'en': 'English',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'it': 'Italian',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh': 'Chinese',
  'hi': 'Hindi',
  'ar': 'Arabic',
  'tr': 'Turkish',
  'th': 'Thai',
  'tl': 'Tagalog',
  'fil': 'Filipino',
  'id': 'Indonesian',
  'vi': 'Vietnamese',
  'nl': 'Dutch',
  'sv': 'Swedish',
  'da': 'Danish',
  'no': 'Norwegian',
  'fi': 'Finnish',
  'pl': 'Polish',
  'cs': 'Czech',
  'el': 'Greek',
  'he': 'Hebrew',
  'hu': 'Hungarian',
  'ro': 'Romanian',
  'uk': 'Ukrainian',
  'ms': 'Malay',
  'fa': 'Persian',
};

/// Returns the display name for a language [code], or the code itself if
/// unknown, or "Unknown" when null/blank.
String languageName(String? code) {
  if (code == null || code.isEmpty) return 'Unknown';
  return _languageNames[code] ?? code.toUpperCase();
}

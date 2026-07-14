/// TMDB image URL builders. Sizes match the Kotlin `TmdbClient` exactly:
/// poster w342, backdrop w1280, card backdrop w780, still w300, profile w185.
const String _imageBase = 'https://image.tmdb.org/t/p/';

String? _build(String size, String? path) {
  if (path == null || path.isEmpty) return null;
  return '$_imageBase$size$path';
}

String? posterUrl(String? path) => _build('w342', path);
String? backdropUrl(String? path) => _build('w1280', path);
String? cardBackdropUrl(String? path) => _build('w780', path);
String? stillUrl(String? path) => _build('w300', path);
String? profileUrl(String? path) => _build('w185', path);

String youTubeUrl(String key) => 'https://www.youtube.com/watch?v=$key';

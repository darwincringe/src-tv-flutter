/// Default text for the subtitle search box: `Mr Robot s01e01`.
String defaultSubtitleSearchText(
  String title, {
  int? season,
  int? episode,
}) {
  final name = title.trim();
  if (season == null || episode == null) return name;
  final code =
      's${season.toString().padLeft(2, '0')}e${episode.toString().padLeft(2, '0')}';
  return name.isEmpty ? code : '$name $code';
}

/// A keyword the search API can use, plus the season and episode to filter.
class SubtitleSearchQuery {
  final String q;
  final int? season;
  final int? episode;

  const SubtitleSearchQuery({required this.q, this.season, this.episode});
}

/// `Mr Robot s01e01` becomes the title plus season 1 episode 1.
/// Text without that ending keeps [season] and [episode] from the player.
SubtitleSearchQuery parseSubtitleSearch(
  String raw, {
  int? season,
  int? episode,
}) {
  final text = raw.trim();
  final match = RegExp(
    r'^(.*?)(?:\s+s(\d{1,2})\s*e(\d{1,3}))\s*$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) {
    return SubtitleSearchQuery(q: text, season: season, episode: episode);
  }
  final title = match.group(1)!.trim();
  return SubtitleSearchQuery(
    q: title.isEmpty ? text : title,
    season: int.parse(match.group(2)!),
    episode: int.parse(match.group(3)!),
  );
}

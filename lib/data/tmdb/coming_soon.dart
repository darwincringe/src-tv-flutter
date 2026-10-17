/// How long a theatrical run still counts as "in theaters" after opening.
const int theatricalWindowDays = 45;

/// TMDB release types that mean a cinema release.
const Set<int> theatricalReleaseTypes = {2, 3};

/// True when TMDB lists the movie on a streaming, free, ads, rent, or buy
/// service in any country. A title people can already watch online is not
/// "Coming Soon".
bool movieAvailableOnline(Object? providersPayload) {
  if (providersPayload is! Map) return false;
  final results = providersPayload['results'];
  if (results is! Map) return false;
  for (final region in results.values) {
    if (region is! Map) continue;
    for (final key in const ['flatrate', 'free', 'ads', 'rent', 'buy']) {
      final list = region[key];
      if (list is List && list.isNotEmpty) return true;
    }
  }
  return false;
}

/// Cinema release dates (theatrical or theatrical-limited) from a TMDB
/// `release_dates` payload.
List<DateTime> theatricalReleaseDates(Object? releasePayload) {
  if (releasePayload is! Map) return const [];
  final results = releasePayload['results'];
  if (results is! List) return const [];
  final dates = <DateTime>[];
  for (final country in results) {
    if (country is! Map) continue;
    final entries = country['release_dates'];
    if (entries is! List) continue;
    for (final entry in entries) {
      if (entry is! Map) continue;
      final type = (entry['type'] as num?)?.toInt();
      if (type == null || !theatricalReleaseTypes.contains(type)) continue;
      final raw = entry['release_date'] as String?;
      final parsed = raw == null ? null : DateTime.tryParse(raw);
      if (parsed != null) dates.add(parsed);
    }
  }
  return dates;
}

/// Coming Soon only for a cinema title that is not already online.
///
/// [theatricalDates] are type 2/3 releases. A date in the future, or within
/// [theatricalWindowDays] of today, still counts. Streaming, digital-only, and
/// older titles do not.
bool movieComingSoon({
  required bool availableOnline,
  required List<DateTime> theatricalDates,
  DateTime? now,
}) {
  if (availableOnline || theatricalDates.isEmpty) return false;
  final clock = now ?? DateTime.now();
  final today = DateTime(clock.year, clock.month, clock.day);
  final earliest = today.subtract(const Duration(days: theatricalWindowDays));
  for (final date in theatricalDates) {
    final day = DateTime(date.year, date.month, date.day);
    if (!day.isBefore(earliest)) return true;
  }
  return false;
}

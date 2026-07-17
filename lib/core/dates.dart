const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Formats a TMDB date string ("2014-03-19") as "Mar 19, 2014". Returns the
/// input unchanged if it can't be parsed, or '' for null/empty.
String formatDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

/// Whether [iso] is a date strictly in the future — used to tag movies /
/// episodes as "Coming Soon".
bool isComingSoon(String? iso) {
  if (iso == null || iso.isEmpty) return false;
  final d = DateTime.tryParse(iso);
  if (d == null) return false;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return d.isAfter(today);
}

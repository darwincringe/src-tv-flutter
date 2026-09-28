/// Whether a browser Back that moved from [left] to [landed] should be ignored.
///
/// Episode changes stay on one player entry, so backing out of a series must
/// not stop on an earlier episode. An identical entry is a duplicate push of
/// the same page, which makes Back look like it did nothing.
bool shouldSkipHistoryEntry(Uri left, Uri landed) {
  if (left.path == landed.path && _sameQuery(left, landed)) return true;
  return _isWatch(left) && left.path == landed.path;
}

bool _isWatch(Uri uri) {
  final segs = uri.pathSegments;
  return segs.length >= 3 && segs.first == 'watch';
}

bool _sameQuery(Uri a, Uri b) {
  if (a.queryParameters.length != b.queryParameters.length) return false;
  for (final key in a.queryParameters.keys) {
    if (a.queryParameters[key] != b.queryParameters[key]) return false;
  }
  return true;
}

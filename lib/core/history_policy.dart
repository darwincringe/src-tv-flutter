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

/// Browser Back left a title and landed on a tab other than the one that
/// opened it. Returns the tab to restore, or null when Back already landed
/// in the right place (or on another title).
String? detailsBackMismatch({
  required Uri left,
  required Uri landed,
  required String shellPath,
}) {
  const shells = {
    '/search',
    '/helper',
    '/home',
    '/movies',
    '/series',
    '/library',
    '/settings',
  };
  if (left.pathSegments.isEmpty || left.pathSegments.first != 'details') {
    return null;
  }
  if (!shells.contains(landed.path) || !shells.contains(shellPath)) {
    return null;
  }
  if (landed.path == shellPath) return null;
  return shellPath;
}

/// Set by the app. Sends the user to the tab that opened the title.
void Function(String path)? onDetailsBackMismatch;

bool _sameQuery(Uri a, Uri b) {
  if (a.queryParameters.length != b.queryParameters.length) return false;
  for (final key in a.queryParameters.keys) {
    if (a.queryParameters[key] != b.queryParameters[key]) return false;
  }
  return true;
}

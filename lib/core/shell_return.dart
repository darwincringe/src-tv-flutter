/// The tab a title was opened from, plus any details pages opened after it.
///
/// Web replaces the shell when it opens a title, so Back cannot rely on the
/// widget still being there. This remembers where to return.
class ShellReturn {
  static const shells = {
    '/search',
    '/helper',
    '/home',
    '/movies',
    '/series',
    '/library',
    '/settings',
  };

  static String shell = '/home';

  /// While a browser Back is being corrected, ignore the wrong tab it lands on.
  static var hold = false;

  static final List<String> _details = [];

  static void onShell(String path) {
    if (hold || !shells.contains(path)) return;
    shell = path;
    _details.clear();
  }

  static void onOpenDetails(String from, String to) {
    if (from.startsWith('/details')) {
      if (_details.isEmpty || _details.last != from) _details.add(from);
    } else {
      _details.clear();
    }
    _details.add(to);
  }

  /// Drop the current title and return the page under it.
  static String pop() {
    if (_details.length > 1) {
      _details.removeLast();
      return _details.last;
    }
    _details.clear();
    return shell;
  }

  /// Browser Back already moved. Keep the stack aligned with where it landed.
  static void landed(String path) {
    if (path.startsWith('/details')) {
      final at = _details.lastIndexOf(path);
      if (at >= 0) {
        _details.removeRange(at + 1, _details.length);
      } else {
        _details.add(path);
      }
      return;
    }
    onShell(path);
  }
}

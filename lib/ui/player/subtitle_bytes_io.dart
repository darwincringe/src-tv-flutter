import 'dart:io';

/// Native byte helpers for [loadSubtitleCues]. Kept in a conditional-import
/// sibling (see subtitle_bytes_web.dart) so `dart:io` never reaches the web
/// build.

/// Gunzip content that is itself a .gz payload (magic bytes 1f 8b).
List<int> maybeGunzip(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    try {
      return gzip.decode(bytes);
    } catch (_) {}
  }
  return bytes;
}

/// Read a locally-uploaded subtitle file (a real path or file:// URI).
Future<List<int>> readLocalBytes(String uri) {
  final path = uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri;
  return File(path).readAsBytes();
}

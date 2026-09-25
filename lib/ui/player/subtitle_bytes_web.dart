// Web byte helpers for loadSubtitleCues. The browser transparently decompresses
// transport gzip, and our subtitle proxy returns already-decoded text, so
// content-level gzip isn't expected on web — pass bytes through. Local-file
// subtitle upload isn't supported on web (no filesystem paths).

List<int> maybeGunzip(List<int> bytes) => bytes;

Future<List<int>> readLocalBytes(String uri) async => const <int>[];

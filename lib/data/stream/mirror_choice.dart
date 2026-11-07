import 'extract_response.dart';

/// Source used when this title has no saved mirror.
const String fallbackMirrorSource = 'vaplayer';

/// Providers requested one at a time. Nashville is not asked for on its own:
/// the server uses it only when a Vaplayer request comes back empty.
const List<String> playbackSources = [
  'vaplayer',
  'movy',
  'flixhq',
  'catflix',
  'ophim',
];

/// Saved source first. With nothing saved, Vaplayer is first. The rest follow
/// in [playbackSources] order, skipping the one already in front.
List<String> playbackSourceQueue(String? preferred) {
  final saved = preferred?.trim().toLowerCase() ?? '';
  if (saved.isEmpty) return List<String>.from(playbackSources);
  final rest = playbackSources.where((source) => source != saved);
  return [saved, ...rest];
}

/// Mirrors that belong to the provider we just asked for. A Vaplayer request
/// may also come back as Nashville when Vaplayer itself had nothing.
List<StreamMirror> mirrorsForPinned(ExtractResponse res, String pinned) {
  final want = pinned.trim().toLowerCase();
  bool keep(String source) {
    final name = source.trim().toLowerCase();
    if (name == want) return true;
    return want == fallbackMirrorSource && name == 'nashville';
  }

  final out = <StreamMirror>[];
  final seen = <String>{};
  for (final mirror in res.mirrors) {
    if (mirror.hlsUrl.isEmpty || !keep(mirror.source)) continue;
    if (seen.add(mirror.hlsUrl)) out.add(mirror);
  }
  final top = res.hlsUrl;
  final topSource = res.source?.trim() ?? '';
  if (top != null &&
      top.isNotEmpty &&
      !seen.contains(top) &&
      (topSource.isEmpty || keep(topSource))) {
    out.insert(
      0,
      StreamMirror(
        hlsUrl: top,
        source: topSource.isEmpty ? pinned : topSource,
        quality: res.quality?.trim() ?? '',
      ),
    );
  }
  return out;
}

/// One step of a playback load. [playUrl] is set only on the first provider
/// that can actually start.
class PlaybackSlice {
  final List<StreamMirror> mirrors;
  final List<String> subtitles;
  final String? playUrl;
  final int playIndex;

  const PlaybackSlice({
    required this.mirrors,
    required this.subtitles,
    this.playUrl,
    this.playIndex = -1,
  });
}

/// Asks for each provider on its own. The first slice that has [PlaybackSlice.playUrl]
/// is the one to start. Later slices only add mirrors and that provider's
/// subtitles.
Stream<PlaybackSlice> playbackSlices({
  required String? preferred,
  required Future<ExtractResponse> Function(String source) extract,
}) async* {
  final mirrors = <StreamMirror>[];
  final subtitles = <String>[];
  final seenUrls = <String>{};
  final seenSubs = <String>{};
  var playing = false;
  for (final source in playbackSourceQueue(preferred)) {
    ExtractResponse res;
    try {
      res = await extract(source);
    } catch (_) {
      continue;
    }
    final before = mirrors.length;
    final subsBefore = subtitles.length;
    for (final mirror in mirrorsForPinned(res, source)) {
      if (seenUrls.add(mirror.hlsUrl)) mirrors.add(mirror);
    }
    for (final line in res.subtitles) {
      if (line.isEmpty || !seenSubs.add(line)) continue;
      subtitles.add(line);
    }
    String? playUrl;
    var playIndex = -1;
    if (!playing && mirrors.length > before) {
      playing = true;
      playIndex = before;
      playUrl = mirrors[before].hlsUrl;
      final top = res.hlsUrl;
      if (top != null && top.isNotEmpty) {
        final at = mirrors.indexWhere((mirror) => mirror.hlsUrl == top);
        if (at >= 0) {
          playIndex = at;
          playUrl = mirrors[at].hlsUrl;
        }
      }
    }
    if (mirrors.length == before && subtitles.length == subsBefore) continue;
    yield PlaybackSlice(
      mirrors: List<StreamMirror>.unmodifiable(mirrors),
      subtitles: List<String>.unmodifiable(subtitles),
      playUrl: playUrl,
      playIndex: playIndex,
    );
  }
}

/// Button text: the provider name plus its quality, e.g. "Catflix 1080p".
String mirrorButtonLabel(int index, StreamMirror mirror) {
  final raw = mirror.source.trim();
  final name = raw.isEmpty
      ? 'Source ${index + 1}'
      : '${raw[0].toUpperCase()}${raw.substring(1)}';
  final quality = mirror.quality.trim();
  if (quality.isEmpty) return name;
  return '$name $quality';
}

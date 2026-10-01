import 'extract_response.dart';

/// Source used when the user's saved mirror is missing from this title.
const String fallbackMirrorSource = 'vaplayer';

/// The URL to play and which row in [ExtractResponse.mirrors] it is.
/// [index] is -1 when the URL is the top-level `hls_url` and not one of the
/// listed mirrors.
class MirrorPick {
  final String url;
  final int index;

  const MirrorPick({required this.url, required this.index});
}

/// Picks what to play.
///
/// A saved [preferred] source wins when that mirror is in the list. If it is
/// not, playback falls back to [fallbackMirrorSource]. With no preference, the
/// response's own `hls_url` is used.
MirrorPick? pickPlayback(ExtractResponse res, String? preferred) {
  final mirrors = res.mirrors;
  final wanted = preferred?.trim().toLowerCase() ?? '';

  StreamMirror? chosen;
  if (wanted.isNotEmpty) {
    chosen = _matchSource(mirrors, wanted) ??
        _matchSource(mirrors, fallbackMirrorSource);
  }
  chosen ??= _matchUrl(mirrors, res.hlsUrl);
  if (chosen == null) {
    final fallbackUrl = res.hlsUrl;
    if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
      return MirrorPick(url: fallbackUrl, index: -1);
    }
    chosen = _matchSource(mirrors, fallbackMirrorSource) ??
        (mirrors.isEmpty ? null : mirrors.first);
  }
  if (chosen == null || chosen.hlsUrl.isEmpty) return null;
  return MirrorPick(url: chosen.hlsUrl, index: mirrors.indexOf(chosen));
}

/// True when [preferred] was requested but the pick is not that source and is
/// not already the Vaplayer fallback — the caller should ask the API again
/// with `source=vaplayer`.
bool needsVaplayerRetry(ExtractResponse res, String? preferred, MirrorPick? pick) {
  final wanted = preferred?.trim().toLowerCase() ?? '';
  if (wanted.isEmpty || wanted == fallbackMirrorSource) return pick == null;
  if (pick == null || pick.index < 0 || pick.index >= res.mirrors.length) {
    return true;
  }
  final playing = res.mirrors[pick.index].source.toLowerCase();
  return playing != wanted && playing != fallbackMirrorSource;
}

/// Loads a stream for [preferred], keeping every mirror available to the picker.
///
/// The saved source is sent as `source` so the backend can select it. If that
/// comes back with only one row, a second request without `source` fills in
/// the rest of the list. When the saved source is not in the list, playback
/// falls back to Vaplayer.
Future<ResolvedPlayback?> resolvePlayback({
  required String? preferred,
  required Future<ExtractResponse> Function(String? source) extract,
}) async {
  final saved = preferred?.trim() ?? '';
  var res = await extract(saved.isEmpty ? null : saved);
  var pick = pickPlayback(res, preferred);
  if (saved.isNotEmpty && res.mirrors.length <= 1) {
    try {
      final full = await extract(null);
      if (full.mirrors.length > res.mirrors.length) {
        final keptUrl = pick?.url;
        res = full;
        pick = pickPlayback(full, preferred) ??
            (keptUrl == null ? null : MirrorPick(url: keptUrl, index: -1));
      }
    } catch (_) {}
  }
  if (needsVaplayerRetry(res, preferred, pick)) {
    try {
      final again = await extract(fallbackMirrorSource);
      final retry = pickPlayback(again, fallbackMirrorSource);
      if (retry != null) {
        final onFullList = _indexOfSource(res.mirrors, fallbackMirrorSource);
        if (onFullList >= 0 && res.mirrors.length >= again.mirrors.length) {
          pick = MirrorPick(url: res.mirrors[onFullList].hlsUrl, index: onFullList);
        } else {
          res = again;
          pick = retry;
        }
      }
    } catch (_) {}
  }
  if (pick == null) return null;
  return ResolvedPlayback(response: res, url: pick.url, index: pick.index);
}

int _indexOfSource(List<StreamMirror> mirrors, String source) {
  for (var i = 0; i < mirrors.length; i++) {
    if (mirrors[i].source.toLowerCase() == source &&
        mirrors[i].hlsUrl.isNotEmpty) {
      return i;
    }
  }
  return -1;
}

class ResolvedPlayback {
  final ExtractResponse response;
  final String url;
  final int index;

  const ResolvedPlayback({
    required this.response,
    required this.url,
    required this.index,
  });
}

StreamMirror? _matchSource(List<StreamMirror> mirrors, String source) {
  for (final m in mirrors) {
    if (m.hlsUrl.isNotEmpty && m.source.toLowerCase() == source) return m;
  }
  return null;
}

StreamMirror? _matchUrl(List<StreamMirror> mirrors, String? url) {
  if (url == null || url.isEmpty) return null;
  for (final m in mirrors) {
    if (m.hlsUrl == url) return m;
  }
  return null;
}

/// Button text. The provider name is intentionally not included.
String mirrorButtonLabel(int index, StreamMirror mirror) {
  final name = 'Source ${index + 1}';
  final quality = mirror.quality.trim();
  if (quality.isEmpty) return name;
  return '$name $quality';
}

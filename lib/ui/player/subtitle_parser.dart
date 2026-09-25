import 'dart:convert';

import 'package:dio/dio.dart';

// Byte read + gunzip live in a conditional-import sibling so `dart:io` never
// reaches the web build.
import 'subtitle_bytes_io.dart'
    if (dart.library.html) 'subtitle_bytes_web.dart';

/// One subtitle cue: when to show [text] and until when.
class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

/// Fetches and parses a subtitle file into cues ourselves, instead of relying
/// on better_player's built-in parser — that parser throws on cues with 3+ text
/// lines (`_handle3LinesAndMoreSubtitles`), which silently killed whole tracks
/// (e.g. High School of the Dead). Returns an empty list on any failure (bad
/// URL, 404 HTML, unsupported content) so the player just shows no subtitles.
Future<List<SubtitleCue>> loadSubtitleCues(String uri, {String? userAgent}) async {
  try {
    List<int> bytes;
    if (uri.startsWith('http')) {
      final resp = await Dio().get<List<int>>(
        uri,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          headers: userAgent != null ? {'User-Agent': userAgent} : null,
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
        ),
      );
      bytes = resp.data ?? const [];
    } else {
      bytes = await readLocalBytes(uri);
    }
    return parseSubtitles(_decode(maybeGunzip(bytes)));
  } catch (_) {
    return const [];
  }
}

String _decode(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes);
  }
}

// (?:HH:)?MM:SS[.,]mmm — hours optional, fractional part 1-3 digits (SRT
// millis or ASS centiseconds; padded to millis in _toDuration).
final _timeRe = RegExp(r'(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{1,3})');

/// Parses SRT, WebVTT, or SubStation Alpha (.ass/.ssa) text into time-ordered
/// cues. ASS is common on OpenSubtitles (e.g. High School of the Dead) — the
/// native app's ExoPlayer decodes it, so we must too.
List<SubtitleCue> parseSubtitles(String content) {
  final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (normalized.contains('[Script Info]') ||
      normalized.contains('[Events]') ||
      RegExp(r'^\s*Dialogue:', multiLine: true).hasMatch(normalized)) {
    return _parseAss(normalized);
  }
  return _parseSrtVtt(normalized);
}

/// SubStation Alpha: the `[Events]` section has a `Format:` line naming the
/// field order, then `Dialogue:` lines. Text is the last field (may contain
/// commas) and carries `{\...}` override tags and `\N` line breaks we strip.
List<SubtitleCue> _parseAss(String content) {
  final cues = <SubtitleCue>[];
  var startIdx = 1, endIdx = 2, textIdx = 9, numFields = 10;
  var inEvents = false;
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('[')) {
      inEvents = line.toLowerCase() == '[events]';
      continue;
    }
    if (!inEvents) continue;
    final lower = line.toLowerCase();
    if (lower.startsWith('format:')) {
      final fields = line
          .substring(line.indexOf(':') + 1)
          .split(',')
          .map((f) => f.trim().toLowerCase())
          .toList();
      numFields = fields.length;
      if (fields.contains('start')) startIdx = fields.indexOf('start');
      if (fields.contains('end')) endIdx = fields.indexOf('end');
      if (fields.contains('text')) textIdx = fields.indexOf('text');
      continue;
    }
    if (!lower.startsWith('dialogue:')) continue;
    final parts = line.substring(line.indexOf(':') + 1).split(',');
    if (parts.length < numFields) continue;
    final sm = _timeRe.firstMatch(parts[startIdx].trim());
    final em = _timeRe.firstMatch(parts[endIdx].trim());
    if (sm == null || em == null) continue;
    final text = _cleanAss(parts.sublist(textIdx).join(','));
    if (text.isEmpty) continue;
    cues.add(SubtitleCue(
      start: _toDuration(sm),
      end: _toDuration(em),
      text: text,
    ));
  }
  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

String _cleanAss(String s) => s
    .replaceAll(RegExp(r'\{[^}]*\}'), '') // override/drawing tags
    .replaceAll(RegExp(r'\\[Nn]'), '\n') // hard/soft line breaks
    .replaceAll(r'\h', ' ') // hard space
    .trim();

/// Parses SRT or WebVTT. Tolerant of a WEBVTT header, cue index numbers, VTT
/// cue settings, and CRLF/CR line endings (already normalised by the caller).
List<SubtitleCue> _parseSrtVtt(String normalized) {
  final cues = <SubtitleCue>[];
  for (final block in normalized.split(RegExp(r'\n[ \t]*\n'))) {
    final lines = block.split('\n');
    var timingIdx = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains('-->')) {
        timingIdx = i;
        break;
      }
    }
    if (timingIdx < 0) continue;
    final times = _timeRe.allMatches(lines[timingIdx]).toList();
    if (times.length < 2) continue;
    final text = lines.sublist(timingIdx + 1).join('\n').trim();
    if (text.isEmpty) continue;
    cues.add(SubtitleCue(
      start: _toDuration(times[0]),
      end: _toDuration(times[1]),
      text: text,
    ));
  }
  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

Duration _toDuration(RegExpMatch m) {
  final h = int.tryParse(m.group(1) ?? '') ?? 0;
  final min = int.parse(m.group(2)!);
  final s = int.parse(m.group(3)!);
  final ms = int.parse(m.group(4)!.padRight(3, '0').substring(0, 3));
  return Duration(hours: h, minutes: min, seconds: s, milliseconds: ms);
}

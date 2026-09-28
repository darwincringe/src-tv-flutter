import 'dart:math' as math;

import 'subtitle_parser.dart';

/// How far to shift subtitle cues, in milliseconds, so they line up with
/// [energy].
///
/// [energy] maps video time in 100ms bins to a voice-band level (higher means
/// someone is talking). Positive means the subtitle file is late, so cues
/// should be shown earlier. Returns 0 when the file is already lined up, and
/// null when there isn't a clear match — a guess is worse than no shift.
int? subtitleSyncOffsetMs(Map<int, double> energy, List<SubtitleCue> cues) {
  if (energy.length < 80 || cues.isEmpty) return null;
  final keys = energy.keys.toList()..sort();
  final levels = energy.values.toList()..sort();
  final noise = levels[(levels.length * 0.4).floor()];
  final cut = math.max(noise * 1.8, 0.12);
  final speechCount = energy.values.where((v) => v >= cut).length;
  // Too little dialogue, or the whole stretch is loud (music, not speech).
  if (speechCount < 20 || speechCount > energy.length * 0.8) return null;

  final sorted = [...cues]..sort((a, b) => a.start.compareTo(b.start));
  bool cueAt(int bin) {
    final t = Duration(milliseconds: bin * 100);
    var lo = 0;
    var hi = sorted.length - 1;
    var idx = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid].start <= t) {
        idx = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (idx < 0) return false;
    for (var i = idx; i >= 0 && i >= idx - 2; i--) {
      final c = sorted[i];
      if (t >= c.start && t <= c.end) return true;
    }
    return false;
  }

  const minLag = -100;
  const maxLag = 100;
  final scores = <int, double>{};
  var bestLag = 0;
  var best = -2.0;
  var atZero = -2.0;
  for (var lag = minLag; lag <= maxLag; lag++) {
    final score = _correlate(keys, energy, cut, lag, cueAt);
    scores[lag] = score;
    if (lag == 0) atZero = score;
    if (score > best) {
      best = score;
      bestLag = lag;
    }
  }
  if (best < 0.28) return null;
  // Already close. A tiny nudge from noise is not worth showing.
  if (atZero >= best - 0.04) return 0;

  var background = 0.0;
  var backgroundCount = 0;
  for (final e in scores.entries) {
    if ((e.key - bestLag).abs() <= 3) continue;
    background += e.value;
    backgroundCount++;
  }
  if (backgroundCount == 0) return null;
  background /= backgroundCount;
  // A real delay is a peak. A flat hill is a guess.
  if (best < background + 0.12) return null;
  return bestLag * 100;
}

double _correlate(
  List<int> bins,
  Map<int, double> energy,
  double cut,
  int lag,
  bool Function(int bin) cueAt,
) {
  var n = 0;
  var sumS = 0.0;
  var sumC = 0.0;
  var sumSS = 0.0;
  var sumCC = 0.0;
  var sumSC = 0.0;
  for (final bin in bins) {
    final s = energy[bin]! >= cut ? 1.0 : 0.0;
    final c = cueAt(bin + lag) ? 1.0 : 0.0;
    sumS += s;
    sumC += c;
    sumSS += s * s;
    sumCC += c * c;
    sumSC += s * c;
    n++;
  }
  if (n < 40) return -1;
  final meanS = sumS / n;
  final meanC = sumC / n;
  final varS = sumSS / n - meanS * meanS;
  final varC = sumCC / n - meanC * meanC;
  if (varS < 1e-6 || varC < 1e-6) return -1;
  return (sumSC / n - meanS * meanC) / math.sqrt(varS * varC);
}

final _wordRe = RegExp(r"[a-z0-9']+");
final _tagRe = RegExp(r'<[^>]*>');
const _stop = {
  'a', 'an', 'the', 'and', 'or', 'to', 'of', 'in', 'on', 'i', 'you', 'it',
  'is', 'was', 'are', 'that', 'this', 'for', 'with', 'my', 'your', 'we',
  'he', 'she', 'they', 'be', 'do', 'did', 'have', 'has',
};

/// Shift so a spoken [transcript], heard at [videoMs], lands on the subtitle
/// line that says the same thing.
///
/// Positive means the subtitle file is late (show that line earlier). Null
/// when the line isn't in the file, or the only hits are too vague to trust.
int? subtitleLineOffsetMs({
  required String transcript,
  required int videoMs,
  required List<SubtitleCue> cues,
}) {
  final spoken = _words(transcript);
  final distinctive = spoken.where(_distinctive).toList();
  if (spoken.length < 4 || distinctive.length < 2 || cues.isEmpty) return null;

  final sorted = [...cues]..sort((a, b) => a.start.compareTo(b.start));
  var bestScore = 0.0;
  var bestStart = 0;
  var bestDistance = 1 << 30;

  for (var i = 0; i < sorted.length; i++) {
    final parts = <String>[];
    for (var n = 0; n < 3 && i + n < sorted.length; n++) {
      if (n > 0) {
        final gap = sorted[i + n].start - sorted[i + n - 1].end;
        if (gap > const Duration(seconds: 3)) break;
      }
      parts.add(sorted[i + n].text);
      final window = _words(parts.join(' '));
      if (window.isEmpty) continue;
      final matched = distinctive.where(window.contains).length;
      if (matched < 2) continue;
      final covered = _lcsCount(spoken, window) / spoken.length;
      if (covered < 0.55) continue;
      final distance = (sorted[i].start.inMilliseconds - videoMs).abs();
      final better = covered > bestScore + 0.05 ||
          ((covered - bestScore).abs() <= 0.05 && distance < bestDistance);
      if (better) {
        bestScore = covered;
        bestStart = sorted[i].start.inMilliseconds;
        bestDistance = distance;
      }
    }
  }
  if (bestScore < 0.55) return null;
  // A repeated line from another scene is not this moment.
  if (bestDistance > 180000) return null;
  final offset = bestStart - videoMs;
  if (offset.abs() < 400) return 0;
  return offset;
}

List<String> _words(String raw) {
  final plain = raw.replaceAll(_tagRe, ' ').toLowerCase();
  return _wordRe.allMatches(plain).map((m) => m.group(0)!).toList();
}

bool _distinctive(String word) => word.length >= 4 && !_stop.contains(word);

int _lcsCount(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  var prev = List<int>.filled(m + 1, 0);
  var cur = List<int>.filled(m + 1, 0);
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      if (a[i - 1] == b[j - 1]) {
        cur[j] = prev[j - 1] + 1;
      } else {
        final left = cur[j - 1];
        final up = prev[j];
        cur[j] = left > up ? left : up;
      }
    }
    final swap = prev;
    prev = cur;
    cur = swap..fillRange(0, swap.length, 0);
  }
  return prev[m];
}

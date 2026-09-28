import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:web/web.dart' as web;

import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../data/introdb/introdb_client.dart';
import '../../data/models/details_dto.dart';
import '../../data/repository/media_repository.dart';
import '../../data/store/subtitle_pref.dart';
import '../../data/store/watch_progress.dart';
import '../../data/sync/sync_service.dart';
import 'player_args.dart';
import 'subtitle_config.dart';
import 'subtitle_parser.dart';
import 'subtitle_sync.dart';

// ---- hls.js interop (bundled in web/hls.min.js, loaded from index.html) -----
@JS('Hls')
external JSAny? get _hlsCtor; // non-null once hls.min.js has loaded

@JS('Hls')
extension type _Hls._(JSObject _) implements JSObject {
  external _Hls([JSAny? config]);
  external void loadSource(String url);
  external void attachMedia(JSObject media);
  external void destroy();
  external JSArray<_HlsLevel> get levels;
  external int get currentLevel; // -1 = auto
  external set currentLevel(int v);
  external static bool isSupported();
}

@JS()
extension type _HlsLevel._(JSObject _) implements JSObject {
  external int get height;
}

bool get _hlsAvailable => _hlsCtor != null && _Hls.isSupported();

@JS('AudioContext')
extension type _AudioCtx._(JSObject _) implements JSObject {
  external factory _AudioCtx();
  external _AudioNode createMediaElementSource(JSObject element);
  external _AnalyserNode createAnalyser();
  external _GainNode createGain();
  external _ScriptProcessor createScriptProcessor(
      int bufferSize, int inputs, int outputs);
  external JSObject get destination;
  external double get sampleRate;
  external JSPromise resume();
}

extension type _GainNode._(JSObject _) implements JSObject {
  external void connect(JSObject destination);
  external _AudioParam get gain;
}

extension type _AudioParam._(JSObject _) implements JSObject {
  external set value(double v);
}

extension type _ScriptProcessor._(JSObject _) implements JSObject {
  external void connect(JSObject destination);
  external set onaudioprocess(JSFunction fn);
}

@JS('srctvTranscribe')
external JSPromise<JSString> _srctvTranscribe(
    JSFloat32Array samples, double sampleRate);

extension type _AudioNode._(JSObject _) implements JSObject {
  external void connect(JSObject destination);
}

extension type _AnalyserNode._(JSObject _) implements JSObject {
  external void connect(JSObject destination);
  external set fftSize(int value);
  external set smoothingTimeConstant(double value);
  external int get frequencyBinCount;
  external void getByteFrequencyData(JSUint8Array array);
}

class _EpisodeRef {
  final int season;
  final int episode;
  const _EpisodeRef(this.season, this.episode);
}

/// Web build of the player (same public name/constructor as the native
/// PlayerScreen; selected via the conditional export in player_view.dart).
/// HTML5 <video> + hls.js with the app's own overlay controls: resume/progress
/// (drives sync), subtitle picker, quality picker, skip recap/intro, next/prev
/// episode + auto-advance.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.args});
  final PlayerArgs args;

  @override
  ConsumerState<PlayerScreen> createState() => _WebPlayerScreenState();
}

class _WebPlayerScreenState extends ConsumerState<PlayerScreen> {
  late final web.HTMLVideoElement _video;
  _Hls? _hls;
  late final String _viewType;

  bool _loading = true;
  String? _errorMsg;
  String? _title;
  bool _playing = false;
  bool _showControls = true;
  bool _fullscreen = false;
  late final JSFunction _fsListener;

  // iOS (all browsers are WebKit): no element Fullscreen API, so we use the
  // <video>'s native fullscreen — which draws its own player chrome and won't
  // show our Flutter subtitle overlay. On iOS we therefore render subtitles as
  // a native WebVTT <track> so they appear in (and out of) native fullscreen.
  late final bool _iosNative;
  web.HTMLTrackElement? _iosTrack;
  String? _iosTrackUrl;

  int _positionMs = 0;
  int _durationMs = 0;
  double _bufferedFraction = 0;

  int _resumeTargetMs = 0;
  bool _resumeDone = true;
  bool _metadataSeekDone = false;

  // Series / episode nav.
  bool _isTv = false;
  List<Season> _seasons = const [];
  int? _season;
  int? _episode;
  String? _episodeName;
  _EpisodeRef? _nextRef;
  _EpisodeRef? _prevRef;

  // Skip recap/intro/outro (introdb) + the current on-screen action.
  MediaSegments? _segments;
  String? _actionKind; // 'intro' | 'recap' | 'next' | null

  List<SubtitleOption> _subs = const [];
  final List<SubtitleOption> _uploaded = [];
  final Map<String, List<SubtitleCue>> _uploadedCues = {};
  int _subIndex = -1; // -1 = off
  List<SubtitleCue> _cues = const [];
  int _subToken = 0;
  String? _cueText;
  bool _autoSync = false;
  int _syncOffsetMs = 0;
  int _syncToken = 0;
  int _syncAttempts = 0;
  final ValueNotifier<String> _syncNote = ValueNotifier('');
  bool _armCapture = false;
  final List<Float32List> _pcmChunks = [];
  int _pcmSamples = 0;
  int? _lineVideoMs;
  Completer<void>? _captureDone;
  _AudioCtx? _audioCtx;
  _AnalyserNode? _analyser;
  bool _audioTapFailed = false;

  Timer? _ticker;
  Timer? _hideTimer;
  int _ticks = 0;

  PlayerArgs get _a => widget.args;
  int get _now => DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    PlayerRuntime.isOpen = true;
    SubtitlePrefStore.revision.addListener(_onRemoteSubtitle);
    SyncService.pullSubtitlePrefs();
    _season = _a.season;
    _episode = _a.episode;
    _viewType = 'srctv-video-$_now';
    _video = web.document.createElement('video') as web.HTMLVideoElement
      ..autoplay = false
      ..controls = false;
    _video.setAttribute('playsinline', 'true');
    // Don't let the <video> grab keyboard focus, so Space/arrows reach Flutter.
    // Clicks are handled by a Flutter PointerInterceptor layer over the video.
    _video.tabIndex = -1;
    _video.style.setProperty('width', '100%');
    _video.style.setProperty('height', '100%');
    _video.style.setProperty('background-color', 'black');
    _video.style.setProperty('object-fit', 'contain');

    ui_web.platformViewRegistry
        .registerViewFactory(_viewType, (int _) => _video);

    _video.addEventListener('loadedmetadata', _onLoadedMetadata.toJS);
    _video.addEventListener('play', ((web.Event _) => _setPlaying(true)).toJS);
    _video.addEventListener('pause', ((web.Event _) => _setPlaying(false)).toJS);
    _video.addEventListener('ended', ((web.Event _) => _onEnded()).toJS);
    _video.addEventListener('error', ((web.Event _) => _onVideoError()).toJS);

    _iosNative = !web.document.fullscreenEnabled &&
        (_video as JSObject).has('webkitEnterFullscreen');

    // Keep the fullscreen toggle in sync when the user enters/exits via the
    // browser (F11, ESC, the video's own affordances).
    _fsListener = ((web.Event _) => _onFullscreenChange()).toJS;
    web.document.addEventListener('fullscreenchange', _fsListener);

    _load();
  }

  Future<void> _load() async {
    if (_a.mode != PlayerMode.stream || _a.tmdbId == null || _a.type == null) {
      setState(() {
        _loading = false;
        _errorMsg = 'Nothing to play';
      });
      return;
    }
    try {
      final repo = ref.read(mediaRepositoryProvider);
      final res = await repo.streamSource(
        _a.type!,
        _a.tmdbId!,
        season: _season,
        episode: _episode,
      );
      if (!mounted) return;
      if (!res.success || (res.hlsUrl?.isEmpty ?? true)) {
        setState(() {
          _loading = false;
          _errorMsg = res.error ?? 'No playable source found';
        });
        return;
      }

      // Details once (title, isTv, seasons for episode nav).
      if (_title == null) {
        try {
          final d = await repo.details(_a.type!, _a.tmdbId!);
          _title = d.title;
          _isTv = d.isTv;
          _seasons = d.seasons;
        } catch (_) {}
      }
      // Episode name for the header.
      if (_isTv && _episode != null) {
        try {
          final eps = await repo.episodes(_a.tmdbId!, _season ?? 1);
          final m = eps.where((e) => e.episodeNumber == _episode);
          _episodeName = m.isNotEmpty ? m.first.name : null;
        } catch (_) {
          _episodeName = null;
        }
      }

      _computeEpisodeRefs();
      _resumeTargetMs = _savedResumePosition();
      _resumeDone = _resumeTargetMs <= 0;
      _subs = [...apiSubtitleOptions(res.subtitles), ..._uploaded];
      // Apply the remembered choice (per-season for TV / per-title for movies),
      // else default to English. Not saved — only user picks persist.
      _selectSubtitle(_initialSubtitleIndex(), save: false);

      if (!mounted) return;
      _attach(res.hlsUrl!);
      if (_isTv && _season != null && _episode != null) {
        _fetchSegments(_season!, _episode!);
      }
      _startTicker();
      setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMsg = 'Playback error';
        });
      }
    }
  }

  void _attach(String hlsUrl) {
    _hls?.destroy();
    _hls = null;
    final canNative =
        _video.canPlayType('application/vnd.apple.mpegurl').isNotEmpty;
    if (_hlsAvailable) {
      // Some upstream source mirrors stall intermittently (a single segment can
      // take 8-10s). Buffer far ahead during the good stretches so an occasional
      // slow segment just drains the cushion instead of freezing playback, and
      // retry failed fragments harder before giving up.
      final config = <String, Object?>{
        'maxBufferLength': 90, // seconds to hold ahead (hls.js default 30)
        'maxMaxBufferLength': 600,
        'backBufferLength': 30,
        'maxBufferSize': 100 * 1000 * 1000, // 100 MB (default 60)
        'fragLoadingMaxRetry': 8,
        'fragLoadingRetryDelay': 500,
        'fragLoadingMaxRetryTimeout': 64000,
        'manifestLoadingMaxRetry': 6,
        'levelLoadingMaxRetry': 6,
      }.jsify();
      final hls = _Hls(config);
      hls.loadSource(hlsUrl);
      hls.attachMedia(_video);
      _hls = hls;
    } else {
      _video.src = hlsUrl; // Safari plays HLS natively; last-resort otherwise
      if (!canNative) {
        // Nothing else to do — some browsers still cope with a direct src.
      }
    }
  }

  int _savedResumePosition() {
    final p = WatchProgressStore.get(_a.type!, _a.tmdbId!);
    if (p == null || !p.isResumable) return 0;
    if (_a.type == 'tv' && (p.season != _season || p.episode != _episode)) {
      return 0;
    }
    return p.positionMs;
  }

  // ---- episode navigation ------------------------------------------------
  int _episodeCount(int season) {
    for (final s in _seasons) {
      if (s.seasonNumber == season) return s.episodeCount ?? 0;
    }
    return 0;
  }

  void _computeEpisodeRefs() {
    _nextRef = null;
    _prevRef = null;
    if (!(_a.type == 'tv' && _season != null && _episode != null)) return;
    final s = _season!;
    final e = _episode!;
    final count = _episodeCount(s);
    if (e < count) {
      _nextRef = _EpisodeRef(s, e + 1);
    } else {
      final later = _seasons
          .where((x) => x.seasonNumber > s && (x.episodeCount ?? 0) > 0)
          .toList()
        ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      if (later.isNotEmpty) _nextRef = _EpisodeRef(later.first.seasonNumber, 1);
    }
    if (e > 1) {
      _prevRef = _EpisodeRef(s, e - 1);
    } else {
      final earlier = _seasons
          .where((x) => x.seasonNumber < s && (x.episodeCount ?? 0) > 0)
          .toList()
        ..sort((a, b) => b.seasonNumber.compareTo(a.seasonNumber));
      if (earlier.isNotEmpty) {
        _prevRef = _EpisodeRef(
            earlier.first.seasonNumber, earlier.first.episodeCount ?? 1);
      }
    }
  }

  void _playEpisode(_EpisodeRef ref) {
    _saveProgress();
    _video.pause();
    _subToken++; // cancel any in-flight subtitle load
    setState(() {
      _season = ref.season;
      _episode = ref.episode;
      _episodeName = null;
      _loading = true;
      _metadataSeekDone = false;
      _durationMs = 0;
      _positionMs = 0;
      _bufferedFraction = 0;
      _subs = const [];
      _subIndex = -1;
      _cues = const [];
      _cueText = null;
      _segments = null;
      _actionKind = null;
      _nextRef = null;
      _prevRef = null;
    });
    _syncEpisodeUrl(ref.season, ref.episode);
    _load();
  }

  Future<void> _fetchSegments(int season, int episode) async {
    try {
      final seg = await ref
          .read(mediaRepositoryProvider)
          .episodeSegments(_a.tmdbId!, season, episode);
      if (!mounted || _season != season || _episode != episode) return;
      setState(() => _segments = seg);
    } catch (_) {}
  }

  // ---- lifecycle events --------------------------------------------------
  void _onLoadedMetadata(web.Event _) {
    final durSec = _video.duration;
    if (durSec.isFinite && durSec > 0) _durationMs = (durSec * 1000).round();
    if (!_metadataSeekDone && _resumeTargetMs > 0) {
      _metadataSeekDone = true;
      _video.currentTime = _resumeTargetMs / 1000.0;
      _resumeDone = true;
    }
    _video.play();
    if (mounted) setState(() => _loading = false);
    _restartHideTimer();
  }

  void _setPlaying(bool p) {
    if (mounted) setState(() => _playing = p);
  }

  void _onEnded() {
    // Auto-advance to the next episode (or mark movie complete).
    _markCompleted();
    if (_isTv && _nextRef != null) _playEpisode(_nextRef!);
  }

  void _onVideoError() {
    if (!mounted) return;
    if (_durationMs == 0) {
      setState(() {
        _loading = false;
        _errorMsg = 'This title could not be played in the browser';
      });
    }
  }

  // ---- ticker ------------------------------------------------------------
  void _startTicker() {
    _ticker?.cancel();
    _ticks = 0;
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final durSec = _video.duration;
      final posSec = _video.currentTime;
      if (durSec.isFinite && durSec > 0) _durationMs = (durSec * 1000).round();
      _positionMs = (posSec * 1000).round();
      try {
        final b = _video.buffered;
        if (b.length > 0 && _durationMs > 0) {
          final end = b.end(b.length - 1);
          _bufferedFraction = (end * 1000 / _durationMs).clamp(0.0, 1.0);
        }
      } catch (_) {}

      _ticks++;
      if (_ticks % 60 == 0) _saveProgress(); // ~30s

      final action = _computeActionKind();
      final changed = action != _actionKind;
      _actionKind = action;
      _updateCue();
      if (mounted && (_showControls || changed)) setState(() {});
    });
  }

  void _updateCue() {
    if (_iosNative) return; // iOS renders cues via the native <track>
    if (_cues.isEmpty) {
      if (_cueText != null && mounted) setState(() => _cueText = null);
      return;
    }
    final pos = Duration(milliseconds: _positionMs + _syncOffsetMs);
    String? text;
    for (final c in _cues) {
      if (pos >= c.start && pos <= c.end) {
        text = c.text;
        break;
      }
      if (c.start > pos) break;
    }
    if (text != _cueText && mounted) setState(() => _cueText = text);
  }

  String? _computeActionKind() {
    if (_a.mode != PlayerMode.stream) return null;
    final posMs = _positionMs;
    final dur = _durationMs;
    final seg = _segments;
    final outro = seg?.outro;
    final outroValid = outro != null && (dur <= 0 || outro.startMs > dur * 0.5);
    if (seg != null) {
      final intro = seg.intro;
      if (intro != null && posMs >= intro.startMs && posMs < intro.endMs) {
        return 'intro';
      }
      final recap = seg.recap;
      if (recap != null && posMs >= recap.startMs && posMs < recap.endMs) {
        return 'recap';
      }
      if (outroValid && posMs >= outro.startMs && _nextRef != null) {
        return 'next';
      }
    }
    if (_isTv && _nextRef != null && dur > 0 && posMs >= dur * 0.95 && !outroValid) {
      return 'next';
    }
    return null;
  }

  // ---- progress ----------------------------------------------------------
  void _saveProgress() {
    if (_a.mode != PlayerMode.stream || !_resumeDone) return;
    final dur = _durationMs;
    if (dur <= 0) return;
    // Closing or the periodic save must keep this episode, even in the credits.
    // Finishing the file (_onEnded) is what advances to the next episode or
    // marks the series complete when there is no next one.
    WatchProgressStore.save(WatchProgress(
      tmdbId: _a.tmdbId!,
      type: _a.type!,
      season: _season,
      episode: _episode,
      positionMs: _positionMs,
      durationMs: dur,
      updatedAt: _now,
      title: _title,
      posterPath: _a.backdropPath,
      completed: false,
    ));
  }

  void _markCompleted() {
    if (_a.mode != PlayerMode.stream) return;
    if (_isTv && _nextRef != null) {
      // Queue the next episode at position 0 so Continue Watching advances.
      WatchProgressStore.save(WatchProgress(
        tmdbId: _a.tmdbId!,
        type: 'tv',
        season: _nextRef!.season,
        episode: _nextRef!.episode,
        positionMs: 0,
        durationMs: 0,
        updatedAt: _now,
        title: _title,
        posterPath: _a.backdropPath,
        completed: false,
      ));
    } else {
      final dur = _durationMs;
      if (dur <= 0) return;
      WatchProgressStore.save(WatchProgress(
        tmdbId: _a.tmdbId!,
        type: _a.type!,
        season: _season,
        episode: _episode,
        positionMs: dur,
        durationMs: dur,
        updatedAt: _now,
        title: _title,
        posterPath: _a.backdropPath,
        completed: true,
      ));
    }
  }

  // ---- subtitles ---------------------------------------------------------
  /// The subtitle to start with: the remembered choice (SubtitlePrefStore —
  /// per-season for TV, per-title for movies), else the first English track,
  /// else off (-1).
  int _initialSubtitleIndex() {
    if (_subs.isEmpty) return -1;
    final remembered = rememberedSubtitleIndex(
      _subs,
      SubtitlePrefStore.get(_a.type!, _a.tmdbId!, _season),
    );
    if (remembered != null) return remembered;
    // Default: first English track (by language code or "eng"/"english" text).
    for (var i = 0; i < _subs.length; i++) {
      final s = _subs[i];
      final hay = '${s.label} ${s.language ?? ''}'.toLowerCase();
      if (s.language == 'en' || hay.contains('english') || hay.contains('eng')) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _selectSubtitle(int index, {bool save = true}) async {
    // Re-tapping the current track (or closing the menu onto it) must not
    // cancel a listen that is already running.
    if (index == _subIndex && _autoSync && _cues.isNotEmpty) return;
    _syncToken++;
    _syncAttempts = 0;
    // Opt-in. Don't check the box from a previous visit, and don't keep a
    // shift from a bad earlier guess. Timing stays on the file's own clock
    // until the viewer turns auto-sync on.
    _autoSync = false;
    _syncOffsetMs = 0;
    _syncNote.value = '';
    setState(() {
      _subIndex = index;
      _cues = const [];
      _cueText = null;
    });
    _clearIosTextTrack();
    if (save) await _persistSubPref(index);
    if (index < 0 || index >= _subs.length) return;
    final token = ++_subToken;
    final uri = _subs[index].uri;
    final cues = _uploadedCues[uri] ?? await loadSubtitleCues(uri);
    if (!mounted || token != _subToken) return;
    setState(() => _cues = cues);
    // On iOS render via a native track (visible in native fullscreen); the
    // Flutter overlay is suppressed there to avoid double subtitles.
    if (_iosNative && cues.isNotEmpty) _applyIosTextTrack(cues, index);
  }

  /// Another device saved a choice for this title. Apply it without writing
  /// back, or the two devices would keep overwriting each other.
  void _onRemoteSubtitle() {
    if (!mounted || _subs.isEmpty) return;
    final pref = SubtitlePrefStore.get(_a.type!, _a.tmdbId!, _season);
    if (pref == null) return;
    final idx = rememberedSubtitleIndex(_subs, pref);
    if (idx == null) return;
    if (idx != _subIndex) {
      if (_autoSync) return;
      _selectSubtitle(idx, save: false);
      return;
    }
    if (!_autoSync || pref.offsetMs == _syncOffsetMs) return;
    _syncOffsetMs = pref.offsetMs;
    if (_iosNative && _subIndex >= 0 && _cues.isNotEmpty) {
      _applyIosTextTrack(_cues, _subIndex);
    }
    if (mounted) setState(() {});
  }

  Future<void> _persistSubPref(int index) {
    final prev = SubtitlePrefStore.get(_a.type!, _a.tmdbId!, _season);
    final pref = index < 0
        ? SubtitlePref(
            off: true,
            name: prev?.name,
            language: prev?.language,
            offsetMs: prev?.offsetMs ?? _syncOffsetMs,
          )
        : SubtitlePref(
            name: _subs[index].label,
            language: subtitlePrefLanguage(_subs[index]),
            autoSync: _autoSync,
            offsetMs: _syncOffsetMs,
          );
    return SubtitlePrefStore.save(_a.type!, _a.tmdbId!, _season, pref);
  }

  Future<void> _setAutoSync(bool on) async {
    _autoSync = on;
    if (!on) {
      _syncToken++;
      _syncAttempts = 0;
      _syncOffsetMs = 0;
      _syncNote.value = '';
    } else {
      _syncAttempts = 0;
      _syncNote.value = 'Listening to the audio…';
    }
    if (mounted) setState(() {});
    await _persistSubPref(_subIndex);
    if (on && _subIndex >= 0 && _cues.isNotEmpty) _beginAutoSync();
  }

  bool _tapAudio() {
    if (_analyser != null) return true;
    if (_audioTapFailed) return false;
    try {
      final ctx = _AudioCtx();
      final source = ctx.createMediaElementSource(_video);
      final analyser = ctx.createAnalyser()
        ..fftSize = 2048
        ..smoothingTimeConstant = 0.35;
      source.connect(analyser);
      analyser.connect(ctx.destination);
      final processor = ctx.createScriptProcessor(4096, 1, 1);
      final mute = ctx.createGain();
      mute.gain.value = 0;
      processor.onaudioprocess = _onPcm.toJS;
      source.connect(processor);
      processor.connect(mute);
      mute.connect(ctx.destination);
      _audioCtx = ctx;
      _analyser = analyser;
      return true;
    } catch (_) {
      _audioTapFailed = true;
      return false;
    }
  }

  void _onPcm(JSObject event) {
    if (!_armCapture || !_autoSync || _video.paused) return;
    final input = event['inputBuffer'] as JSObject?;
    if (input == null) return;
    final data = input.callMethod<JSFloat32Array>('getChannelData'.toJS, 0.toJS);
    final view = data.toDart;
    var energy = 0.0;
    var counted = 0;
    for (var i = 0; i < view.length; i += 8) {
      final v = view[i];
      energy += v * v;
      counted++;
    }
    final loud = counted > 0 && energy / counted > 0.0004;
    if (_lineVideoMs == null) {
      if (!loud) return;
      final t = _video.currentTime;
      if (!t.isFinite || t < 0) return;
      // This buffer already played, so the sentence started one buffer ago.
      final bufferSec = view.length / (_audioCtx?.sampleRate ?? 48000);
      final start = t - bufferSec;
      _lineVideoMs = ((start < 0 ? 0 : start) * 1000).round();
    }
    _pcmChunks.add(Float32List.fromList(view));
    _pcmSamples += view.length;
    final rate = _audioCtx?.sampleRate ?? 48000;
    if (_pcmSamples / rate >= 6) {
      _armCapture = false;
      final done = _captureDone;
      if (done != null && !done.isCompleted) done.complete();
    }
  }

  Future<({Float32List samples, double rate, int videoMs})?> _captureLine(
    int token,
  ) async {
    _pcmChunks.clear();
    _pcmSamples = 0;
    _lineVideoMs = null;
    final done = Completer<void>();
    _captureDone = done;
    _armCapture = true;
    final started = DateTime.now();
    while (!done.isCompleted &&
        DateTime.now().difference(started) < const Duration(seconds: 22)) {
      if (!mounted || token != _syncToken || !_autoSync) {
        _armCapture = false;
        return null;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _armCapture = false;
    final rate = _audioCtx?.sampleRate ?? 0;
    final startMs = _lineVideoMs;
    if (startMs == null || rate <= 0 || _pcmSamples < rate * 2) return null;
    final merged = Float32List(_pcmSamples);
    var offset = 0;
    for (final chunk in _pcmChunks) {
      merged.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _pcmChunks.clear();
    _pcmSamples = 0;
    return (samples: merged, rate: rate, videoMs: startMs);
  }

  /// Text of one spoken sentence, and how far into the recording it began.
  Future<({String text, int startMs})?> _readLine(
    Float32List samples,
    double rate,
  ) async {
    try {
      final raw =
          (await _srctvTranscribe(samples.toJS, rate).toDart).toDart;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final start = (decoded['start'] as num?)?.toDouble() ?? 0;
        return (
          text: (decoded['text'] ?? '').toString(),
          startMs: start > 0 ? (start * 1000).round() : 0,
        );
      }
      return (text: raw, startMs: 0);
    } catch (_) {
      return null;
    }
  }

  /// Hears one spoken line, finds that line in the subtitle file, and shifts
  /// the captions so the file's timestamp matches the video.
  Future<void> _beginAutoSync() async {
    final token = ++_syncToken;
    if (_subIndex < 0 || _cues.isEmpty || !_autoSync) {
      if (_subIndex < 0) _syncNote.value = 'Choose a subtitle first';
      return;
    }
    if (!_tapAudio()) {
      _finishSyncNote(
          'This stream doesn’t share its audio, so auto-sync can’t run');
      return;
    }
    try {
      await _audioCtx!.resume().toDart;
    } catch (_) {}
    _syncNote.value = 'Listening for a line of dialogue…';
    final clip = await _captureLine(token);
    if (!mounted || token != _syncToken || !_autoSync) return;
    if (clip == null) {
      if (_syncAttempts >= 2) {
        _finishSyncNote('Couldn’t hear a clear line of dialogue');
        return;
      }
      _syncAttempts++;
      _syncNote.value = 'Not enough dialogue yet — still listening';
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || token != _syncToken || !_autoSync) return;
      return _beginAutoSync();
    }
    _syncNote.value =
        'Reading that line… the first time also downloads a speech model';
    final heard = await _readLine(clip.samples, clip.rate);
    if (!mounted || token != _syncToken || !_autoSync) return;
    if (heard == null) {
      _finishSyncNote('Couldn’t read the dialogue from this stream');
      return;
    }
    final quote = heard.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final offset = subtitleLineOffsetMs(
      transcript: quote,
      videoMs: clip.videoMs + heard.startMs,
      cues: _cues,
    );
    if (offset == null) {
      if (_syncAttempts >= 2) {
        final shown = quote.length > 80 ? '${quote.substring(0, 77)}…' : quote;
        _finishSyncNote(shown.isEmpty
            ? 'Couldn’t hear a clear line of dialogue'
            : 'Heard “$shown” but couldn’t find that line in the subtitles');
        return;
      }
      _syncAttempts++;
      _syncNote.value = 'That line wasn’t in the subtitles — listening again';
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || token != _syncToken || !_autoSync) return;
      return _beginAutoSync();
    }
    _syncAttempts = 0;
    _syncOffsetMs = offset;
    final secs = (offset.abs() / 1000).toStringAsFixed(1);
    _finishSyncNote(offset == 0
        ? 'Already lined up'
        : offset > 0
            ? 'Shifted ${secs}s earlier'
            : 'Shifted ${secs}s later');
    if (_iosNative && _subIndex >= 0) _applyIosTextTrack(_cues, _subIndex);
    await _persistSubPref(_subIndex);
    if (mounted) setState(() {});
  }

  // ---- iOS native subtitle track (WebVTT) --------------------------------
  void _applyIosTextTrack(List<SubtitleCue> cues, int index) {
    try {
      _clearIosTextTrack();
      final shift = Duration(milliseconds: _syncOffsetMs);
      final shifted = shift == Duration.zero
          ? cues
          : [
              for (final c in cues)
                SubtitleCue(
                  start: c.start - shift,
                  end: c.end - shift,
                  text: c.text,
                ),
            ];
      final vtt = _cuesToVtt(shifted);
      final blob = web.Blob(
        [vtt.toJS].toJS,
        web.BlobPropertyBag(type: 'text/vtt'),
      );
      final url = web.URL.createObjectURL(blob);
      final track =
          web.document.createElement('track') as web.HTMLTrackElement;
      track.setAttribute('kind', 'subtitles');
      track.setAttribute('label', _subs[index].label);
      final lang = _subs[index].language;
      if (lang != null && lang.isNotEmpty) track.setAttribute('srclang', lang);
      track.setAttribute('src', url);
      track.setAttribute('default', '');
      _video.append(track);
      _iosTrack = track;
      _iosTrackUrl = url;
      // Force the freshly-added track to display.
      track.track.mode = 'showing';
    } catch (_) {}
  }

  void _clearIosTextTrack() {
    try {
      _iosTrack?.remove();
      if (_iosTrackUrl != null) web.URL.revokeObjectURL(_iosTrackUrl!);
    } catch (_) {}
    _iosTrack = null;
    _iosTrackUrl = null;
  }

  static String _cuesToVtt(List<SubtitleCue> cues) {
    final b = StringBuffer('WEBVTT\n\n');
    for (final c in cues) {
      b.writeln('${_vttTime(c.start)} --> ${_vttTime(c.end)}');
      b.writeln(_fixCommaSpacing(_sanitizeVttText(c.text)));
      b.writeln();
    }
    return b.toString();
  }

  // WebVTT natively renders <i>/<b>/<u>; keep those and drop any other tag
  // (e.g. <font color=...>) so it isn't shown literally on iOS.
  static final RegExp _tagRe = RegExp(r'</?([a-zA-Z]+)[^>]*>');
  static String _sanitizeVttText(String raw) => raw.replaceAllMapped(_tagRe,
      (m) {
    final t = m.group(1)!.toLowerCase();
    return (t == 'i' || t == 'b' || t == 'u') ? m.group(0)! : '';
  });

  static String _vttTime(Duration d) {
    final ms = d.inMilliseconds;
    String two(int x) => x.toString().padLeft(2, '0');
    final h = ms ~/ 3600000;
    final m = (ms ~/ 60000) % 60;
    final s = (ms ~/ 1000) % 60;
    final milli = (ms % 1000).toString().padLeft(3, '0');
    return '${two(h)}:${two(m)}:${two(s)}.$milli';
  }

  /// Reads an SRT (or VTT/ASS) the viewer picks and plays it with the same
  /// timing controls as a downloaded track, including auto-sync.
  Future<bool> _uploadSubtitle() async {
    const group = XTypeGroup(
      label: 'subtitles',
      extensions: ['srt', 'vtt', 'ass', 'ssa'],
    );
    final XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: [group]);
    } catch (_) {
      _snack('Couldn’t open that subtitle file');
      return false;
    }
    if (file == null || !mounted) return false;
    List<SubtitleCue> cues;
    try {
      cues = parseSubtitleBytes(await file.readAsBytes());
    } catch (_) {
      cues = const [];
    }
    if (!mounted) return false;
    if (cues.isEmpty) {
      _snack('Couldn’t read any lines from that subtitle');
      return false;
    }
    final rawName = file.name.trim();
    var label = rawName.isEmpty ? 'Uploaded' : rawName;
    var n = 2;
    while (_subs.any((s) => s.label == label) ||
        _uploaded.any((s) => s.label == label)) {
      label = '${rawName.isEmpty ? 'Uploaded' : rawName} $n';
      n++;
    }
    final id = 'upload:${_uploaded.length}';
    final opt = SubtitleOption(
      uri: id,
      label: label,
      language: detectLanguage(label),
    );
    _uploaded.add(opt);
    _uploadedCues[id] = cues;
    setState(() => _subs = [..._subs, opt]);
    await _selectSubtitle(_subs.length - 1);
    if (mounted) _snack('Subtitle added');
    return true;
  }

  Future<void> _showSubtitleMenu() async {
    final wasPlaying = _playing;
    _hideTimer?.cancel();
    final labels = <String>['Off', for (final s in _subs) s.label];
    final picked = await showDialog<int>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _SubtitleMenu(
        labels: labels,
        current: _subIndex + 1, // row 0 = Off
        autoSync: _autoSync,
        note: _syncNote,
        onAutoSync: _setAutoSync,
        onUpload: _uploadSubtitle,
      ),
    );
    if (picked != null) _selectSubtitle(picked - 1); // -1 = Off
    if (wasPlaying) {
      _restartHideTimer();
      if (_video.paused) _video.play();
    }
  }

  // ---- quality -----------------------------------------------------------
  Future<void> _showQualityMenu() async {
    final hls = _hls;
    if (hls == null) {
      _snack('Quality control is only available on this browser via hls.js');
      return;
    }
    // Build a de-duplicated, highest-first list of heights → hls level index.
    final levels = hls.levels.toDart;
    final byHeight = <int, int>{}; // height -> level index
    for (var i = 0; i < levels.length; i++) {
      final h = levels[i].height;
      if (h > 0) byHeight.putIfAbsent(h, () => i);
    }
    if (byHeight.isEmpty) {
      _snack('Only one quality available');
      return;
    }
    final heights = byHeight.keys.toList()..sort((a, b) => b.compareTo(a));
    final labels = <String>['Auto', for (final h in heights) '${h}p'];
    final cur = hls.currentLevel; // -1 = auto
    var currentRow = 0;
    if (cur >= 0 && cur < levels.length) {
      final ch = levels[cur].height;
      final idx = heights.indexOf(ch);
      if (idx >= 0) currentRow = idx + 1;
    }
    final wasPlaying = _playing;
    _hideTimer?.cancel();
    final picked = await showDialog<int>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _PickerMenu(
        title: 'Quality',
        labels: labels,
        current: currentRow,
      ),
    );
    if (picked != null) {
      hls.currentLevel = picked == 0 ? -1 : (byHeight[heights[picked - 1]] ?? -1);
    }
    if (wasPlaying) _restartHideTimer();
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ---- controls ----------------------------------------------------------
  void _performAction() {
    switch (_actionKind) {
      case 'intro':
        if (_segments?.intro != null) _seekToMs(_segments!.intro!.endMs);
        break;
      case 'recap':
        if (_segments?.recap != null) _seekToMs(_segments!.recap!.endMs);
        break;
      case 'next':
        if (_nextRef != null) _playEpisode(_nextRef!);
        break;
    }
  }

  void _togglePlay() {
    _video.paused ? _video.play() : _video.pause();
    _restartHideTimer();
  }

  void _seekBy(int deltaMs) => _seekToMs(_positionMs + deltaMs);

  void _seekToMs(int ms) {
    final dur = _durationMs;
    final clamped = ms.clamp(0, dur > 0 ? dur : ms);
    _video.currentTime = clamped / 1000.0;
    setState(() => _positionMs = clamped);
    _restartHideTimer();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _restartHideTimer();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    if (!mounted) return;
    if (!_showControls) setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _showControls = false);
    });
  }

  Future<void> _exit() async {
    _saveProgress();
    PlayerRuntime.leftAt = _now;
    if (!context.mounted) return;
    // On web (go-based nav) fall back to this title's details page.
    final fb = (_a.type != null && _a.tmdbId != null)
        ? '/details/${_a.type}/${_a.tmdbId}'
        : '/home';
    navBack(context, fallback: fb);
  }

  // Keep the address bar on the episode actually playing without adding a
  // history entry. Back then leaves the player for details, instead of
  // stepping through earlier episodes. Refresh and share still use this URL.
  void _syncEpisodeUrl(int season, int episode) {
    if (_a.type != 'tv' || _a.tmdbId == null || !mounted) return;
    final loc = watchLocation(
      type: 'tv',
      tmdbId: _a.tmdbId!,
      season: season,
      episode: episode,
    );
    final here = GoRouterState.of(context).uri;
    final next = Uri.parse(loc);
    if (here.path == next.path &&
        here.queryParameters['s'] == next.queryParameters['s'] &&
        here.queryParameters['e'] == next.queryParameters['e']) {
      return;
    }
    Router.neglect(context, () => context.replace(loc));
  }

  // ---- Fullscreen --------------------------------------------------------
  // Fullscreen the whole app document (not just the <video>) so the Flutter
  // overlay controls stay visible and interactive while fullscreen.
  void _toggleFullscreen() {
    try {
      if (web.document.fullscreenEnabled) {
        // Standard path (desktop, Android Chrome, iPadOS Safari): fullscreen the
        // whole app so the Flutter overlay controls stay visible.
        if (web.document.fullscreenElement != null) {
          web.document.exitFullscreen();
        } else {
          web.document.documentElement?.requestFullscreen();
        }
      } else {
        // iPhone / iOS: every browser is WebKit and there is NO element
        // Fullscreen API — only the <video>'s native fullscreen works. iOS
        // shows its own player chrome and provides its own exit control.
        final v = _video as JSObject;
        if (v.has('webkitEnterFullscreen')) {
          v.callMethod<JSAny?>('webkitEnterFullscreen'.toJS);
        }
      }
    } catch (_) {}
  }

  void _onFullscreenChange() {
    final fs = web.document.fullscreenElement != null;
    if (fs != _fullscreen && mounted) setState(() => _fullscreen = fs);
  }

  @override
  void dispose() {
    _syncToken++;
    _syncNote.dispose();
    SubtitlePrefStore.revision.removeListener(_onRemoteSubtitle);
    _ticker?.cancel();
    _hideTimer?.cancel();
    _saveProgress();
    PlayerRuntime.leftAt = _now;
    PlayerRuntime.isOpen = false;
    web.document.removeEventListener('fullscreenchange', _fsListener);
    _clearIosTextTrack();
    try {
      if (web.document.fullscreenElement != null) web.document.exitFullscreen();
    } catch (_) {}
    try {
      _video.pause();
      _hls?.destroy();
      _video.src = '';
      _video.removeAttribute('src');
      _video.load();
    } catch (_) {}
    super.dispose();
  }

  static String _fmt(int ms) {
    if (ms <= 0) return '0:00';
    final s = ms ~/ 1000;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  // ---- UI ----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            HtmlElementView(viewType: _viewType),
            // Always-on click catcher over the <video> (PointerInterceptor lets
            // Flutter receive clicks over the platform view). Tapping toggles
            // controls; when controls show, their layer below sits on top.
            Positioned.fill(
              child: PointerInterceptor(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                ),
              ),
            ),
            if (!_iosNative && _cueText != null) _subtitleOverlay(),
            if (_autoSync) _syncStatus(),
            if (_errorMsg == null && !_loading && _actionKind != null)
              PointerInterceptor(child: _skipActionOverlay()),
            if (_loading) _loaderOverlay(),
            if (_errorMsg != null) PointerInterceptor(child: _errorOverlay()),
            if (_errorMsg == null && !_loading && _showControls)
              PointerInterceptor(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  child: _controlsOverlay(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final isSelect = key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.mediaPlayPause;
    if (isSelect) {
      // When a Skip/Next action is on screen, the select key triggers it
      // (mirrors the TV remote landing on the Skip button); otherwise play/pause.
      if (_actionKind != null) {
        _performAction();
      } else {
        _togglePlay();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-10000);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(10000);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      // In fullscreen, ESC drops out of fullscreen rather than closing the
      // player (mirrors native browser behaviour).
      if (web.document.fullscreenElement != null) {
        _toggleFullscreen();
      } else {
        _exit();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _loaderOverlay() => Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(_headerTitle(),
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );

  Widget _errorOverlay() => Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMsg!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
            const SizedBox(height: 16),
            TextButton(onPressed: _exit, child: const Text('Back')),
          ],
        ),
      );

  /// Small status while captions are being lined up. It does not block the
  /// movie, and it goes away a few seconds after a result.
  Widget _syncStatus() {
    return Positioned(
      top: 28,
      left: 24,
      right: 24,
      child: IgnorePointer(
        child: ValueListenableBuilder<String>(
          valueListenable: _syncNote,
          builder: (_, text, _) {
            if (text.isEmpty) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.topCenter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _finishSyncNote(String text) {
    _syncNote.value = text;
    final token = _syncToken;
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted || token != _syncToken) return;
      if (_syncNote.value == text) _syncNote.value = '';
    });
  }

  Widget _subtitleOverlay() {
    // Same sizing as the Android player: a fraction of screen width, so a
    // browser window gets the same scale as the TV/phone overlay (capped).
    final fontSize =
        (MediaQuery.of(context).size.width * 0.032).clamp(20.0, 44.0);
    return Positioned(
      left: 24,
      right: 24,
      bottom: _showControls ? 96 : 40,
      child: IgnorePointer(
        child: Text.rich(
          TextSpan(children: _parseCueSpans(_cueText!)),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            height: 1.2,
            shadows: const [
              Shadow(
                  offset: Offset(0, 1), blurRadius: 6, color: Color(0xCC000000)),
              Shadow(
                  offset: Offset(0, 0), blurRadius: 14, color: Color(0x99000000)),
            ],
          ),
        ),
      ),
    );
  }

  // Subtitle cues carry SRT/HTML-ish markup (<i>, <b>, <u>, <font ...>) and
  // entities (&amp; &lt; &#39; …). Render the styling and drop unknown tags so
  // the tags never show up as literal text.
  static List<InlineSpan> _parseCueSpans(String raw) {
    raw = _fixCommaSpacing(raw);
    final spans = <InlineSpan>[];
    var italic = false, bold = false, underline = false;
    final buf = StringBuffer();
    void flush() {
      if (buf.isEmpty) return;
      spans.add(TextSpan(
        text: _decodeEntities(buf.toString()),
        style: TextStyle(
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          fontWeight: bold ? FontWeight.w800 : null,
          decoration: underline ? TextDecoration.underline : null,
        ),
      ));
      buf.clear();
    }

    var i = 0;
    while (i < raw.length) {
      final lt = raw.indexOf('<', i);
      if (lt < 0) {
        buf.write(raw.substring(i));
        break;
      }
      buf.write(raw.substring(i, lt));
      final gt = raw.indexOf('>', lt);
      if (gt < 0) {
        buf.write(raw.substring(lt)); // stray '<', not a tag
        break;
      }
      flush();
      final tag = raw.substring(lt + 1, gt).trim().toLowerCase();
      if (tag == 'i') {
        italic = true;
      } else if (tag == '/i') {
        italic = false;
      } else if (tag == 'b') {
        bold = true;
      } else if (tag == '/b') {
        bold = false;
      } else if (tag == 'u') {
        underline = true;
      } else if (tag == '/u') {
        underline = false;
      } // any other tag (font, etc.) is dropped
      i = gt + 1;
    }
    flush();
    return spans;
  }

  static String _decodeEntities(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&'); // '&' last so we don't re-decode

  // Some source subtitles omit the space after a comma ("buy in,the"). Insert
  // one when a comma is directly followed by a non-space, non-digit character
  // (so decimals/thousands like "1,000" are left alone). Also fixes a comma
  // that sat right before a stripped tag ("in,<i>the" → "in, the").
  static final RegExp _commaNoSpace = RegExp(r',(?=[^\s\d])');
  static String _fixCommaSpacing(String s) =>
      s.replaceAll(_commaNoSpace, ', ');

  String _headerTitle() {
    var t = _title ?? '';
    if (_isTv && _season != null && _episode != null) {
      final se = 'S$_season·E$_episode';
      t = t.isEmpty ? se : '$t — $se';
      if (_episodeName != null && _episodeName!.isNotEmpty) {
        t = '$t: $_episodeName';
      }
    }
    return t;
  }

  Widget _skipActionOverlay() {
    final kind = _actionKind!;
    late final String label;
    late final IconData icon;
    switch (kind) {
      case 'intro':
        label = 'Skip Intro';
        icon = Icons.fast_forward;
        break;
      case 'recap':
        label = 'Skip Recap';
        icon = Icons.fast_forward;
        break;
      default:
        label = 'Next Episode';
        icon = Icons.skip_next;
    }
    return Positioned(
      right: 28,
      bottom: _showControls ? 132 : 48,
      child: _SkipButton(label: label, icon: icon, onTap: _performAction),
    );
  }

  Widget _controlsOverlay() {
    final hasQuality = _hls != null;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x99000000), Color(0x00000000), Color(0x99000000)],
          stops: [0, 0.4, 1],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  onPressed: _exit,
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _headerTitle(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isTv)
                IconButton(
                  iconSize: 34,
                  onPressed: _prevRef != null ? () => _playEpisode(_prevRef!) : null,
                  icon: const Icon(Icons.skip_previous),
                  color: Colors.white,
                  disabledColor: Colors.white24,
                  tooltip: 'Previous episode',
                ),
              const SizedBox(width: 12),
              _RoundBtn(icon: Icons.replay, label: '15', onTap: () => _seekBy(-15000)),
              const SizedBox(width: 20),
              IconButton(
                iconSize: 64,
                onPressed: _togglePlay,
                icon: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 20),
              _RoundBtn(
                  icon: Icons.replay,
                  label: '15',
                  flip: true,
                  onTap: () => _seekBy(15000)),
              const SizedBox(width: 12),
              if (_isTv)
                IconButton(
                  iconSize: 34,
                  onPressed: _nextRef != null ? () => _playEpisode(_nextRef!) : null,
                  icon: const Icon(Icons.skip_next),
                  color: Colors.white,
                  disabledColor: Colors.white24,
                  tooltip: 'Next episode',
                ),
            ],
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Text(_fmt(_positionMs),
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(width: 10),
                Expanded(child: _seekBar()),
                const SizedBox(width: 10),
                Text(_fmt(_durationMs),
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                if (hasQuality) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _showQualityMenu,
                    tooltip: 'Quality',
                    icon: const Icon(Icons.high_quality_outlined,
                        color: Colors.white),
                  ),
                ],
                IconButton(
                  onPressed: _showSubtitleMenu,
                  tooltip: _subIndex < 0
                      ? 'Subtitles'
                      : 'Subtitles: ${_subs[_subIndex].label}',
                  icon: Icon(
                    _subIndex < 0
                        ? Icons.closed_caption_off_outlined
                        : Icons.closed_caption,
                    color: _subIndex < 0 ? Colors.white70 : Colors.white,
                  ),
                ),
                IconButton(
                  onPressed: _uploadSubtitle,
                  tooltip: 'Upload SRT',
                  icon: const Icon(Icons.upload_file, color: Colors.white),
                ),
                IconButton(
                  onPressed: _toggleFullscreen,
                  tooltip: _fullscreen ? 'Exit full screen' : 'Full screen',
                  icon: Icon(
                    _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seekBar() {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final frac =
            _durationMs > 0 ? (_positionMs / _durationMs).clamp(0.0, 1.0) : 0.0;
        void seekTo(double dx) {
          if (_durationMs <= 0) return;
          _seekToMs(((dx / w).clamp(0.0, 1.0) * _durationMs).round());
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekTo(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
          child: SizedBox(
            height: 24,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(height: 4, color: Colors.white24),
                FractionallySizedBox(
                  widthFactor: _bufferedFraction,
                  child: Container(height: 4, color: Colors.white38),
                ),
                FractionallySizedBox(
                  widthFactor: frac,
                  child: Container(height: 4, color: Colors.white),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Circular seek button with a number label (rewind/forward 15).
class _RoundBtn extends StatelessWidget {
  const _RoundBtn(
      {required this.icon, required this.onTap, this.label, this.flip = false});
  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final bool flip;

  @override
  Widget build(BuildContext context) {
    Widget arrow = Icon(icon, color: Colors.white, size: 34);
    if (flip) arrow = Transform.flip(flipX: true, child: arrow);
    return IconButton(
      onPressed: onTap,
      icon: Stack(
        alignment: Alignment.center,
        children: [
          arrow,
          if (label != null)
            Text(label!,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// Prominent Skip Recap / Skip Intro / Next Episode button; autofocuses so the
/// keyboard/remote select key triggers it.
class _SkipButton extends StatefulWidget {
  const _SkipButton(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_SkipButton> createState() => _SkipButtonState();
}

class _SkipButtonState extends State<_SkipButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onFocusChange: (f) => setState(() => _focused = f),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        }),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: _focused ? Colors.white : Colors.black54,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon,
                  size: 20, color: _focused ? Colors.black : Colors.white),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: _focused ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Subtitle list plus auto-sync. Pops the chosen row.
class _SubtitleMenu extends StatefulWidget {
  const _SubtitleMenu({
    required this.labels,
    required this.current,
    required this.autoSync,
    required this.note,
    required this.onAutoSync,
    required this.onUpload,
  });
  final List<String> labels;
  final int current;
  final bool autoSync;
  final ValueNotifier<String> note;
  final ValueChanged<bool> onAutoSync;
  final Future<bool> Function() onUpload;

  @override
  State<_SubtitleMenu> createState() => _SubtitleMenuState();
}

class _SubtitleMenuState extends State<_SubtitleMenu> {
  late bool _autoSync = widget.autoSync;

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: Align(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380, maxHeight: 520),
          child: Material(
            color: AppColors.charcoalLight,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Subtitles',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.labels.length,
                    itemBuilder: (context, i) => _MenuRow(
                      label: widget.labels[i],
                      selected: i == widget.current,
                      autofocus: i == widget.current,
                      onTap: () => Navigator.pop(context, i),
                    ),
                  ),
                ),
                const Divider(height: 1, color: Colors.white24),
                _MenuRow(
                  label: 'Upload SRT',
                  selected: false,
                  onTap: () async {
                    final added = await widget.onUpload();
                    if (added && context.mounted) Navigator.pop(context);
                  },
                ),
                const Divider(height: 1, color: Colors.white24),
                CheckboxListTile(
                  value: _autoSync,
                  onChanged: (v) {
                    final on = v ?? false;
                    setState(() => _autoSync = on);
                    widget.onAutoSync(on);
                    // Leave the menu so the movie stays visible while it listens.
                    if (on && widget.current > 0) Navigator.pop(context);
                  },
                  activeColor: Colors.white,
                  checkColor: Colors.black,
                  dense: true,
                  title: const Text(
                    'Auto-sync timing (Beta)',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                  ),
                  subtitle: ValueListenableBuilder<String>(
                    valueListenable: widget.note,
                    builder: (_, text, _) => Text(
                      text.isEmpty
                          ? 'Hears one line, finds it in the subtitles, and shifts the timing. You can keep watching.'
                          : text,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Generic list picker (subtitles / quality). Keyboard (arrows + Enter) and
/// mouse both work; wrapped in a PointerInterceptor because it floats over the
/// <video> platform view. Pops the chosen 0-based index, or null.
class _PickerMenu extends StatelessWidget {
  const _PickerMenu(
      {required this.title, required this.labels, required this.current});
  final String title;
  final List<String> labels;
  final int current;

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Align(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380, maxHeight: 460),
            child: Material(
              color: AppColors.charcoalLight,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: FocusTraversalGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(title,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close,
                                color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: labels.length,
                        itemBuilder: (context, i) => _MenuRow(
                          label: labels[i],
                          selected: i == current,
                          autofocus: i == current,
                          onTap: () => Navigator.pop(context, i),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.autofocus = false});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        }),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: _focused ? Colors.white24 : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight:
                        widget.selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (widget.selected)
                const Icon(Icons.check, color: AppColors.textPrimary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

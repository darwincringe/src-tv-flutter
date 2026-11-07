import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
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
import '../../data/store/mirror_pref.dart';
import '../../data/store/saved_subtitle.dart';
import '../../data/store/subtitle_offset.dart';
import '../../data/store/subtitle_pref.dart';
import '../../data/subtitle/subtitle_search.dart';
import '../../data/store/watch_progress.dart';
import '../../data/stream/extract_response.dart';
import '../../data/stream/mirror_choice.dart';
import '../../data/sync/sync_service.dart';
import 'mirror_bar.dart';
import 'player_args.dart';
import 'sound_boost.dart';
import 'sound_pref.dart';
import 'subtitle_config.dart';
import 'subtitle_parser.dart';
import 'subtitle_search_dialog.dart';
import 'subtitle_timing.dart';

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
  external _BiquadFilter createBiquadFilter();
  external _DynamicsCompressor createDynamicsCompressor();
  external _GainNode createGain();
  external JSObject get destination;
  external JSPromise resume();
  external JSPromise close();
}

extension type _GainNode._(JSObject _) implements JSObject {
  external void connect(JSObject destination);
  external _AudioParam get gain;
}

extension type _AudioParam._(JSObject _) implements JSObject {
  external set value(double v);
}

extension type _AudioNode._(JSObject _) implements JSObject {
  external void connect(JSObject destination);
}

extension type _BiquadFilter._(JSObject _) implements JSObject {
  external void connect(JSObject destination);
  external set type(String value);
  external _AudioParam get frequency;
  @JS('Q')
  external _AudioParam get q;
  external _AudioParam get gain;
}

extension type _DynamicsCompressor._(JSObject _) implements JSObject {
  external void connect(JSObject destination);
  external _AudioParam get threshold;
  external _AudioParam get knee;
  external _AudioParam get ratio;
  external _AudioParam get attack;
  external _AudioParam get release;
}

class _EpisodeRef {
  final int season;
  final int episode;
  const _EpisodeRef(this.season, this.episode);
}

/// The TV package is still this web player. Arrow keys there must open the
/// controls and move a visible focus ring, the same way the Android remote
/// does. Seeking starts only after the timeline is focused and selected.
const _tizenWeb = bool.fromEnvironment('TIZEN_WEB');

/// Web build of the player (same public name/constructor as the native
/// PlayerScreen; selected via the conditional export in player_view.dart).
/// HTML5 <video> + hls.js with the app's own overlay controls: resume/progress
/// (drives sync), subtitle picker, quality picker, sound booster, skip
/// recap/intro, next/prev episode + auto-advance.
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
  final FocusScopeNode _rootScope = FocusScopeNode(debugLabel: 'player-root');
  final FocusNode _backFocus = FocusNode(debugLabel: 'back');
  final FocusNode _prevFocus = FocusNode(debugLabel: 'prev');
  final FocusNode _rewFocus = FocusNode(debugLabel: 'rew');
  final FocusNode _playPauseFocus = FocusNode(debugLabel: 'playpause');
  final FocusNode _ffFocus = FocusNode(debugLabel: 'ff');
  final FocusNode _nextFocus = FocusNode(debugLabel: 'next');
  final FocusNode _seekFocus = FocusNode(debugLabel: 'seek');
  final FocusNode _soundFocus = FocusNode(debugLabel: 'sound');
  final FocusNode _qualityFocus = FocusNode(debugLabel: 'quality');
  final FocusNode _subFocus = FocusNode(debugLabel: 'subs');
  final FocusNode _fullFocus = FocusNode(debugLabel: 'fullscreen');
  final FocusNode _skipFocus = FocusNode(debugLabel: 'skip');
  bool _scrubbing = false;
  int _scrubPreviewMs = 0;
  bool _wasPlayingBeforeScrub = false;
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
  bool _notedWatched = false;
  bool _metadataSeekDone = false;

  // Progress for one episode must not be written against another. The video
  // element keeps the previous episode's clock until the new file loads, so
  // saves stay closed across that gap.
  int _mediaToken = 0;
  int _metadataToken = -1;
  bool _progressReady = false;
  bool _pickedSubtitle = false;

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

  // Mirrors for the title currently playing. The saved source is per movie,
  // or once for a whole TV series (every season).
  List<StreamMirror> _mirrors = const [];
  int _mirrorIndex = -1;
  final List<FocusNode> _mirrorNodes = [];

  List<SubtitleOption> _subs = const [];
  final List<SubtitleOption> _uploaded = [];
  final Map<String, List<SubtitleCue>> _uploadedCues = {};
  int _subIndex = -1; // -1 = off
  List<SubtitleCue> _cues = const [];
  int _subToken = 0;
  String? _cueText;
  int _syncOffsetMs = 0;
  _AudioCtx? _audioCtx;
  _BiquadFilter? _lowCut;
  _BiquadFilter? _lowShelf;
  _BiquadFilter? _presence;
  _BiquadFilter? _highShelf;
  _DynamicsCompressor? _compressor;
  _GainNode? _makeup;
  bool _audioReady = false;
  bool _audioTapFailed = false;
  SoundMode _soundMode = SoundMode.off;
  JSFunction? _gestureKick;
  JSFunction? _remoteBackFn;

  Timer? _ticker;
  Timer? _hideTimer;
  int _ticks = 0;

  PlayerArgs get _a => widget.args;
  int get _now => DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    PlayerRuntime.isOpen = true;
    _bindRemoteBack();
    _soundMode = SoundPrefStore.mode;
    // A saved booster can't start until the browser sees a click or key,
    // because routing the video through Web Audio needs that gesture.
    // Until then the video plays with its normal sound.
    if (_soundMode != SoundMode.off) {
      _gestureKick = ((web.Event _) => _kickSavedSound()).toJS;
      web.document.addEventListener('pointerdown', _gestureKick!);
      web.document.addEventListener('keydown', _gestureKick!);
    }
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
    final token = _mediaToken;
    if (_a.mode != PlayerMode.stream || _a.tmdbId == null || _a.type == null) {
      setState(() {
        _loading = false;
        _errorMsg = 'Nothing to play';
      });
      return;
    }
    _loadOffset();
    _pickedSubtitle = false;
    _applyMirrors(const [], -1);
    try {
      final repo = ref.read(mediaRepositoryProvider);
      final meta = _loadPlaybackMeta(repo, token);
      List<String> wyzie = const [];
      try {
        wyzie = await repo.englishSubtitles(
          _a.type!,
          _a.tmdbId!,
          season: _season,
          episode: _episode,
        );
      } catch (_) {}
      if (!mounted || token != _mediaToken) return;
      _applySubtitleUrls(wyzie);

      final season = _a.type == 'tv' ? _season : null;
      var started = false;
      await for (final slice in playbackSlices(
        preferred: MirrorPrefStore.get(_a.type!, _a.tmdbId!, season),
        extract: (source) => repo.streamSource(
          _a.type!,
          _a.tmdbId!,
          season: _season,
          episode: _episode,
          source: source,
        ),
      )) {
        if (!mounted || token != _mediaToken) return;
        _applySubtitleUrls(mergeSubtitleUrls(wyzie, slice.subtitles));
        if (!started && slice.playUrl != null) {
          started = true;
          _applyMirrors(slice.mirrors, slice.playIndex);
          _resumeTargetMs = _savedResumePosition();
          // Stay closed until this file's own metadata event. A 0 here means
          // the saved record belongs to a different episode, so playback starts
          // over.
          _resumeDone = false;
          _progressReady = false;
          _metadataSeekDone = false;
          _metadataToken = token;
          _attach(slice.playUrl!);
          setState(() {});
        } else {
          final playing = _urlAt(_mirrorIndex);
          _applyMirrors(slice.mirrors, _indexOfUrl(slice.mirrors, playing));
          if (mounted) setState(() {});
        }
      }
      await meta;
      if (!mounted || token != _mediaToken) return;
      if (!started) {
        setState(() {
          _loading = false;
          _errorMsg = 'No playable source found';
        });
      }
    } catch (_) {
      if (mounted && token == _mediaToken) {
        setState(() {
          _loading = false;
          _errorMsg = 'Playback error';
        });
      }
    }
  }

  String? _urlAt(int index) {
    if (index < 0 || index >= _mirrors.length) return null;
    return _mirrors[index].hlsUrl;
  }

  int _indexOfUrl(List<StreamMirror> mirrors, String? url) {
    if (url == null || url.isEmpty) return -1;
    return mirrors.indexWhere((mirror) => mirror.hlsUrl == url);
  }

  Future<void> _loadPlaybackMeta(MediaRepository repo, int token) async {
    if (_title == null && _a.tmdbId != null && _a.type != null) {
      try {
        final d = await repo.details(_a.type!, _a.tmdbId!, extras: false);
        if (!mounted || token != _mediaToken) return;
        _title = d.title;
        _isTv = d.isTv;
        _seasons = d.seasons;
      } catch (_) {}
    }
    if (!mounted || token != _mediaToken) return;
    if (_isTv && _episode != null && _a.tmdbId != null) {
      try {
        final eps = await repo.episodes(_a.tmdbId!, _season ?? 1);
        if (!mounted || token != _mediaToken) return;
        final match = eps.where((e) => e.episodeNumber == _episode);
        _episodeName = match.isNotEmpty ? match.first.name : null;
      } catch (_) {
        _episodeName = null;
      }
    }
    if (!mounted || token != _mediaToken) return;
    _computeEpisodeRefs();
    if (_isTv && _season != null && _episode != null && _a.tmdbId != null) {
      _fetchSegments(_season!, _episode!);
    }
    if (mounted) setState(() {});
  }

  void _applySubtitleUrls(List<String> apiUrls) {
    final previous = (_subIndex >= 0 && _subIndex < _subs.length)
        ? _subs[_subIndex].uri
        : null;
    _subs = _withSavedSubtitle(
      [...apiSubtitleOptions(apiUrls), ..._uploaded],
    );
    if (previous != null) {
      final kept = _subs.indexWhere((opt) => opt.uri == previous);
      if (kept >= 0) {
        _subIndex = kept;
        if (mounted) setState(() {});
        return;
      }
    }
    if (_subs.isEmpty) {
      if (_a.type != null &&
          _a.tmdbId != null &&
          SubtitlePrefStore.get(_a.type!, _a.tmdbId!, _season)?.off == true) {
        _pickedSubtitle = true;
      }
      if (mounted) setState(() {});
      return;
    }
    if (_pickedSubtitle) {
      if (mounted) setState(() {});
      return;
    }
    _selectSubtitle(_initialSubtitleIndex(), save: false);
  }

  void _applyMirrors(List<StreamMirror> mirrors, int index) {
    _mirrors = mirrors;
    _mirrorIndex = index;
    while (_mirrorNodes.length < mirrors.length) {
      _mirrorNodes.add(FocusNode(debugLabel: 'mirror${_mirrorNodes.length}'));
    }
    while (_mirrorNodes.length > mirrors.length) {
      _mirrorNodes.removeLast().dispose();
    }
  }

  void _selectMirror(int index) {
    if (_loading || index < 0 || index >= _mirrors.length || index == _mirrorIndex) {
      return;
    }
    final mirror = _mirrors[index];
    final pos = _positionMs;
    MirrorPrefStore.save(
      _a.type!,
      _a.tmdbId!,
      mirror.source,
      _a.type == 'tv' ? _season : null,
    );
    // Keep the timestamp across the source change. loadedmetadata applies it.
    _resumeTargetMs = pos;
    _metadataSeekDone = false;
    _metadataToken = _mediaToken;
    _resumeDone = false;
    _progressReady = false;
    setState(() => _mirrorIndex = index);
    _attach(mirror.hlsUrl);
    _restartHideTimer();
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
    _noteWatchedMilestone(_positionMs, _durationMs);
    _notedWatched = false;
    _saveProgress();
    // Close the books before the episode number changes. Otherwise the ticker
    // writes this episode's clock onto the next one, and the next file opens
    // at the previous ending.
    _mediaToken++;
    _metadataToken = -1;
    _resumeDone = false;
    _progressReady = false;
    _resumeTargetMs = 0;
    _metadataSeekDone = true;
    _ticker?.cancel();
    _video.pause();
    _subToken++; // cancel any in-flight subtitle load
    setState(() {
      _season = ref.season;
      _episode = ref.episode;
      _episodeName = null;
      _loading = true;
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
    if (_metadataToken != _mediaToken) return;
    _metadataToken = -1;
    final durSec = _video.duration;
    if (durSec.isFinite && durSec > 0) _durationMs = (durSec * 1000).round();
    if (!_metadataSeekDone) {
      _metadataSeekDone = true;
      // A different episode always starts at its own saved point, or at 0.
      // Assigning 0 also clears a currentTime left behind by the previous file.
      _video.currentTime = _resumeTargetMs / 1000.0;
      _positionMs = _resumeTargetMs;
    }
    _resumeDone = true;
    _progressReady = true;
    _startTicker();
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

      _noteWatchedMilestone(_positionMs, _durationMs);
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
    final pos = Duration(milliseconds: _positionMs - _syncOffsetMs);
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
  void _noteWatchedMilestone(int positionMs, int durationMs) {
    if (_notedWatched || !_resumeDone || _a.mode != PlayerMode.stream) return;
    if (!reachedWatchedThreshold(positionMs, durationMs)) return;
    _notedWatched = true;
    final id = _a.tmdbId;
    final type = _a.type;
    if (id == null || type == null) return;
    if (_isTv && _season != null && _episode != null) {
      WatchProgressStore.rememberEpisode(type, id, _season!, _episode!);
    } else if (!_isTv) {
      WatchProgressStore.rememberMovie(type, id);
    }
  }

  void _saveProgress() {
    if (_a.mode != PlayerMode.stream || !_resumeDone || !_progressReady) return;
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
      posterPath: _a.posterPath ?? _a.backdropPath,
      posterChecked: _a.posterPath != null && _a.posterPath!.isNotEmpty,
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
        posterPath: _a.posterPath ?? _a.backdropPath,
      posterChecked: _a.posterPath != null && _a.posterPath!.isNotEmpty,
        completed: false,
      ), finishedSeason: _season, finishedEpisode: _episode);
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
        posterPath: _a.posterPath ?? _a.backdropPath,
      posterChecked: _a.posterPath != null && _a.posterPath!.isNotEmpty,
        completed: true,
      ));
    }
  }

  // ---- subtitles ---------------------------------------------------------
  List<SubtitleOption> _withSavedSubtitle(List<SubtitleOption> subs) {
    if (_a.tmdbId == null || _a.type == null) return subs;
    final saved = SavedSubtitleStore.get(
      _a.type!,
      _a.tmdbId!,
      _isTv ? _season : null,
      _isTv ? _episode : null,
    );
    if (saved == null) return subs;
    final uri = 'saved:${saved.fileId}';
    _uploadedCues[uri] = parseSubtitles(saved.body);
    return [
      ...subs.where((s) => !s.uri.startsWith('saved:')),
      SubtitleOption(uri: uri, label: saved.label, language: saved.language),
    ];
  }

  Future<bool> _searchSubtitle() async {
    final chosen = await showSubtitleSearchDialog(
      context,
      initialQuery: defaultSubtitleSearchText(
        _title ?? '',
        season: _isTv ? _season : null,
        episode: _isTv ? _episode : null,
      ),
      title: _title ?? '',
      tmdbId: _a.tmdbId ?? 0,
      type: _a.type ?? 'movie',
      season: _isTv ? _season : null,
      episode: _isTv ? _episode : null,
    );
    if (chosen == null || !mounted || _a.type == null || _a.tmdbId == null) {
      return false;
    }
    final cues = parseSubtitles(chosen.body);
    if (cues.isEmpty) {
      _snack('Couldn’t read any lines from that subtitle');
      return false;
    }
    await SavedSubtitleStore.save(
      _a.type!,
      _a.tmdbId!,
      _isTv ? _season : null,
      _isTv ? _episode : null,
      SavedSubtitle(
        fileId: chosen.fileId,
        label: chosen.label,
        language: chosen.language,
        body: chosen.body,
      ),
    );
    final uri = 'saved:${chosen.fileId}';
    _uploadedCues[uri] = cues;
    final opt = SubtitleOption(
      uri: uri,
      label: chosen.label,
      language: chosen.language,
    );
    setState(() {
      _subs = [..._subs.where((s) => !s.uri.startsWith('saved:')), opt];
    });
    await _selectSubtitle(_subs.length - 1);
    if (mounted) _snack('Subtitle saved for this title');
    return true;
  }

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
    _pickedSubtitle = true;
    _subToken++;
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
      _selectSubtitle(idx, save: false);
      return;
    }
  }

  Future<void> _persistSubPref(int index) {
    final prev = SubtitlePrefStore.get(_a.type!, _a.tmdbId!, _season);
    final pref = index < 0
        ? SubtitlePref(
            off: true,
            name: prev?.name,
            language: prev?.language,
            offsetMs: 0,
          )
        : SubtitlePref(
            name: _subs[index].label,
            language: subtitlePrefLanguage(_subs[index]),
            autoSync: false,
            offsetMs: 0,
          );
    return SubtitlePrefStore.save(_a.type!, _a.tmdbId!, _season, pref);
  }

  void _loadOffset() {
    if (_a.type == null || _a.tmdbId == null) return;
    _syncOffsetMs = SubtitleOffsetStore.get(
      _a.type!,
      _a.tmdbId!,
      _isTv ? _season : null,
      _isTv ? _episode : null,
    );
  }

  Future<void> _applyOffset(int offsetMs) async {
    _syncOffsetMs = offsetMs;
    if (_a.type != null && _a.tmdbId != null) {
      await SubtitleOffsetStore.save(
        _a.type!,
        _a.tmdbId!,
        _isTv ? _season : null,
        _isTv ? _episode : null,
        offsetMs,
      );
    }
    if (_iosNative && _subIndex >= 0 && _cues.isNotEmpty) {
      _applyIosTextTrack(_cues, _subIndex);
    }
    _updateCue();
    if (mounted) setState(() {});
  }

  /// Route the video through an equalizer. Once this runs, the <video>
  /// element no longer plays audio on its own, so it must only happen from
  /// a click or key press — otherwise the soundtrack goes silent.
  bool _ensureAudio() {
    if (_audioReady) return true;
    if (_audioTapFailed) return false;
    try {
      final ctx = _AudioCtx();
      final source = ctx.createMediaElementSource(_video);
      final lowCut = ctx.createBiquadFilter()..type = 'highpass';
      final lowShelf = ctx.createBiquadFilter()..type = 'lowshelf';
      final presence = ctx.createBiquadFilter()..type = 'peaking';
      final highShelf = ctx.createBiquadFilter()..type = 'highshelf';
      final compressor = ctx.createDynamicsCompressor();
      final makeup = ctx.createGain();
      source.connect(lowCut);
      lowCut.connect(lowShelf);
      lowShelf.connect(presence);
      presence.connect(highShelf);
      highShelf.connect(compressor);
      compressor.connect(makeup);
      makeup.connect(ctx.destination);
      _audioCtx = ctx;
      _lowCut = lowCut;
      _lowShelf = lowShelf;
      _presence = presence;
      _highShelf = highShelf;
      _compressor = compressor;
      _makeup = makeup;
      _audioReady = true;
      _applySoundCurve();
      return true;
    } catch (_) {
      _audioTapFailed = true;
      return false;
    }
  }

  void _kickSavedSound() {
    final kick = _gestureKick;
    if (kick != null) {
      web.document.removeEventListener('pointerdown', kick);
      web.document.removeEventListener('keydown', kick);
      _gestureKick = null;
    }
    if (_soundMode == SoundMode.off) return;
    if (!_ensureAudio()) return;
    _audioCtx?.resume();
  }

  void _applySoundCurve() {
    final curve = SoundCurve.forMode(_soundMode);
    final lowCut = _lowCut;
    final lowShelf = _lowShelf;
    final presence = _presence;
    final highShelf = _highShelf;
    final compressor = _compressor;
    final makeup = _makeup;
    if (lowCut == null ||
        lowShelf == null ||
        presence == null ||
        highShelf == null ||
        compressor == null ||
        makeup == null) {
      return;
    }
    lowCut.frequency.value = curve.highpassHz;
    lowCut.q.value = 0.7;
    lowShelf.frequency.value = curve.lowShelfHz;
    lowShelf.gain.value = curve.lowShelfDb;
    lowShelf.q.value = 0.7;
    presence.frequency.value = curve.presenceHz;
    presence.gain.value = curve.presenceDb;
    presence.q.value = curve.presenceQ;
    highShelf.frequency.value = curve.highShelfHz;
    highShelf.gain.value = curve.highShelfDb;
    highShelf.q.value = 0.7;
    compressor.threshold.value = curve.thresholdDb;
    compressor.knee.value = curve.kneeDb;
    compressor.ratio.value = curve.ratio;
    compressor.attack.value = curve.attackSec;
    compressor.release.value = curve.releaseSec;
    makeup.gain.value = curve.makeup;
  }

  void _setSoundMode(SoundMode mode) {
    _soundMode = mode;
    SoundPrefStore.save(mode);
    if (mode != SoundMode.off || _audioReady) {
      if (!_ensureAudio()) {
        _snack('This browser can’t boost the sound');
      } else {
        _applySoundCurve();
        _audioCtx?.resume();
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _showSoundMenu() async {
    final wasPlaying = _playing;
    _hideTimer?.cancel();
    final modes = SoundMode.values;
    await showDialog<int>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _PickerMenu(
        title: 'Sound',
        labels: [for (final m in modes) m.label],
        details: [for (final m in modes) m.detail],
        current: modes.indexOf(_soundMode),
        // Apply inside the tap so the browser still counts it as a gesture.
        onSelected: (i) => _setSoundMode(modes[i]),
      ),
    );
    if (wasPlaying) _restartHideTimer();
  }


  // ---- iOS native subtitle track (WebVTT) --------------------------------
  void _applyIosTextTrack(List<SubtitleCue> cues, int index) {
    try {
      _clearIosTextTrack();
      final shift = Duration(milliseconds: -_syncOffsetMs);
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
        offsetMs: _syncOffsetMs,
        onOffset: _applyOffset,
        onUpload: _uploadSubtitle,
        onSearch: _searchSubtitle,
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
    final clamped = ms.clamp(0, dur > 0 ? dur : ms).round();
    _noteWatchedMilestone(clamped, dur);
    _video.currentTime = clamped / 1000.0;
    setState(() => _positionMs = clamped);
    _restartHideTimer();
  }

  void _toggleControls() {
    if (_tizenWeb && _showControls) {
      _hideControls();
      return;
    }
    if (_tizenWeb) {
      _revealControls();
      return;
    }
    setState(() => _showControls = !_showControls);
    if (_showControls) _restartHideTimer();
  }

  void _revealControls() {
    final wasHidden = !_showControls;
    if (wasHidden) setState(() => _showControls = true);
    _restartHideTimer();
    if (_tizenWeb && wasHidden) _focusPlay();
  }

  void _focusPlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _playPauseFocus.canRequestFocus) {
        _playPauseFocus.requestFocus();
      }
    });
  }

  void _hideControls() {
    _hideTimer?.cancel();
    setState(() {
      _showControls = false;
      _scrubbing = false;
    });
    _rootScope.requestFocus();
  }

  void _enterScrub() {
    _scrubPreviewMs = _positionMs;
    _wasPlayingBeforeScrub = _playing;
    _video.pause();
    setState(() => _scrubbing = true);
    _restartHideTimer();
  }

  void _scrubStep(int deltaMs) {
    final dur = _durationMs;
    var t = _scrubPreviewMs + deltaMs;
    if (t < 0) t = 0;
    if (dur > 0 && t > dur) t = dur;
    setState(() => _scrubPreviewMs = t);
    _restartHideTimer();
  }

  void _commitScrub() {
    _seekToMs(_scrubPreviewMs);
    setState(() => _scrubbing = false);
    if (_playPauseFocus.canRequestFocus) _playPauseFocus.requestFocus();
  }

  void _cancelScrub() {
    if (_wasPlayingBeforeScrub) _video.play();
    setState(() => _scrubbing = false);
    if (_playPauseFocus.canRequestFocus) _playPauseFocus.requestFocus();
    _restartHideTimer();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    if (!mounted) return;
    if (!_showControls) setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_playing || _scrubbing) return;
      setState(() => _showControls = false);
      if (_tizenWeb) _rootScope.requestFocus();
    });
  }

  void _bindRemoteBack() {
    if (!_tizenWeb) return;
    _remoteBackFn = (() {
      if (!mounted) return;
      if (_showControls) {
        if (_scrubbing && _wasPlayingBeforeScrub) _video.play();
        _hideControls();
        return;
      }
      _exit();
    }).toJS;
    web.window.setProperty('__srctvOnBack'.toJS, _remoteBackFn!);
  }

  void _unbindRemoteBack() {
    if (!_tizenWeb) return;
    web.window.setProperty('__srctvOnBack'.toJS, null);
  }

  Future<void> _exit() async {
    _saveProgress();
    PlayerRuntime.leftAt = _now;
    if (!context.mounted) return;
    // On the TV, the remote Back key leaves through browser history. The
    // on-screen button has to do that too. The website path checks Flutter's
    // history serial, which this packaged build does not fill in.
    if (_tizenWeb) {
      web.window.history.back();
      return;
    }
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
    final kick = _gestureKick;
    if (kick != null) {
      web.document.removeEventListener('pointerdown', kick);
      web.document.removeEventListener('keydown', kick);
    }
    try {
      _audioCtx?.close();
    } catch (_) {}
    SubtitlePrefStore.revision.removeListener(_onRemoteSubtitle);
    _ticker?.cancel();
    _hideTimer?.cancel();
    for (final node in _mirrorNodes) {
      node.dispose();
    }
    _saveProgress();
    PlayerRuntime.leftAt = _now;
    PlayerRuntime.isOpen = false;
    _unbindRemoteBack();
    _rootScope.dispose();
    for (final node in [
      _backFocus,
      _prevFocus,
      _rewFocus,
      _playPauseFocus,
      _ffFocus,
      _nextFocus,
      _seekFocus,
      _soundFocus,
      _qualityFocus,
      _subFocus,
      _fullFocus,
      _skipFocus,
    ]) {
      node.dispose();
    }
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
      body: FocusScope(
        node: _rootScope,
        // On a TV the play button owns focus while the controls are up, so
        // arrows can move between them. On the website this scope stays
        // focused and the arrow keys seek.
        autofocus: !_tizenWeb,
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
            // Above the controls so Skip stays clickable, and only as big as
            // the button — a full-screen catcher here would eat taps and the
            // pause button and timeline could never be shown.
            if (_errorMsg == null && !_loading && _actionKind != null)
              _skipActionOverlay(),
          ],
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_tizenWeb) return _onTvKey(event);
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
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
    // A mirror or transport button has focus. Leave Select and the arrows to
    // it so a remote can move between the controls and activate one.
    final focused = FocusManager.instance.primaryFocus;
    if (focused != null && focused != node) {
      return KeyEventResult.ignored;
    }
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
    return KeyEventResult.ignored;
  }

  bool _isSelectKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.mediaPlayPause ||
      key == LogicalKeyboardKey.gameButtonA;

  bool _isArrowKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown;

  /// Remote behavior matching the Android player. The center button still
  /// pauses while the controls are hidden. Any arrow only reveals the
  /// controls and lands on play/pause. Seeking happens on the timeline,
  /// after it is focused and selected.
  KeyEventResult _onTvKey(KeyEvent event) {
    // A sound, quality, or subtitle dialog is on top. Leave its keys alone.
    if (ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (web.document.fullscreenElement != null) {
        _toggleFullscreen();
      } else {
        _exit();
      }
      return KeyEventResult.handled;
    }
    if (_errorMsg != null || _loading) return KeyEventResult.ignored;
    final select = _isSelectKey(key);
    final arrow = _isArrowKey(key);
    if (!_showControls) {
      if (_actionKind != null && select) {
        _performAction();
        return KeyEventResult.handled;
      }
      if (select) {
        _togglePlay();
        _focusPlay();
        return KeyEventResult.handled;
      }
      if (arrow) {
        _revealControls();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_scrubbing) {
      _restartHideTimer();
      return KeyEventResult.ignored;
    }
    _restartHideTimer();
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null || focused == _rootScope) {
      if (select) {
        _togglePlay();
        return KeyEventResult.handled;
      }
      _playPauseFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (arrow) {
      _moveTvFocus(key);
      return KeyEventResult.handled;
    }
    if (select && event is KeyDownEvent) {
      _activateTv(focused);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  List<List<FocusNode>> _tvRows() {
    List<FocusNode> live(Iterable<FocusNode> nodes) =>
        nodes.where((n) => n.context != null).toList();
    final rows = <List<FocusNode>>[
      live([_backFocus]),
      live(_mirrorNodes),
      live([
        if (_isTv) _prevFocus,
        _rewFocus,
        _playPauseFocus,
        _ffFocus,
        if (_isTv) _nextFocus,
      ]),
      live([_seekFocus, _soundFocus, _qualityFocus, _subFocus, _fullFocus]),
    ];
    // Skip sits in the corner. It is its own stop so Left/Right on the
    // timeline cannot leap over to it.
    if (_skipFocus.context != null) rows.add([_skipFocus]);
    rows.removeWhere((row) => row.isEmpty);
    return rows;
  }

  void _moveTvFocus(LogicalKeyboardKey key) {
    final rows = _tvRows();
    final current = FocusManager.instance.primaryFocus;
    var r = -1;
    var c = -1;
    for (var i = 0; i < rows.length; i++) {
      final j = rows[i].indexOf(current ?? _rootScope);
      if (j >= 0) {
        r = i;
        c = j;
        break;
      }
    }
    if (r < 0) {
      _playPauseFocus.requestFocus();
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (c > 0) rows[r][c - 1].requestFocus();
      return;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (c + 1 < rows[r].length) rows[r][c + 1].requestFocus();
      return;
    }
    final down = key == LogicalKeyboardKey.arrowDown;
    if (!down && key != LogicalKeyboardKey.arrowUp) return;
    // The timeline is wide. Down from it would land on Skip in the corner.
    if (down && current == _seekFocus) return;
    final next = r + (down ? 1 : -1);
    if (next < 0 || next >= rows.length) return;
    _closest(rows[next], rows[r][c]).requestFocus();
  }

  FocusNode _closest(List<FocusNode> row, FocusNode from) {
    final origin = from.rect.center.dx;
    var best = row.first;
    var bestDx = double.infinity;
    for (final node in row) {
      final dx = (node.rect.center.dx - origin).abs();
      if (dx < bestDx) {
        bestDx = dx;
        best = node;
      }
    }
    return best;
  }

  void _activateTv(FocusNode focused) {
    if (focused == _backFocus) {
      _exit();
    } else if (focused == _prevFocus && _prevRef != null) {
      _playEpisode(_prevRef!);
    } else if (focused == _rewFocus) {
      _seekBy(-15000);
    } else if (focused == _playPauseFocus) {
      _togglePlay();
    } else if (focused == _ffFocus) {
      _seekBy(15000);
    } else if (focused == _nextFocus && _nextRef != null) {
      _playEpisode(_nextRef!);
    } else if (focused == _seekFocus) {
      _enterScrub();
    } else if (focused == _soundFocus) {
      _showSoundMenu();
    } else if (focused == _qualityFocus) {
      _showQualityMenu();
    } else if (focused == _subFocus) {
      _showSubtitleMenu();
    } else if (focused == _fullFocus) {
      _toggleFullscreen();
    } else if (focused == _skipFocus) {
      _performAction();
    } else {
      final mirror = _mirrorNodes.indexOf(focused);
      if (mirror >= 0 && mirror < _mirrors.length) _selectMirror(mirror);
    }
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
      child: PointerInterceptor(
        child: _SkipButton(
          label: label,
          icon: icon,
          onTap: _performAction,
          focusNode: _tizenWeb ? _skipFocus : null,
          autofocus: !_tizenWeb,
        ),
      ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _tizenWeb
                        ? _TvIconButton(
                            icon: Icons.arrow_back,
                            focusNode: _backFocus,
                            onTap: _exit,
                          )
                        : IconButton(
                            onPressed: _exit,
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white),
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
                if (_mirrors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 48, top: 2),
                    child: MirrorBar(
                      mirrors: _mirrors,
                      selected: _mirrorIndex,
                      focusNodes: _mirrorNodes,
                      onSelect: _selectMirror,
                    ),
                  ),
              ],
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isTv && (!_tizenWeb || _prevRef != null))
                _tizenWeb
                    ? _TvIconButton(
                        icon: Icons.skip_previous,
                        focusNode: _prevFocus,
                        onTap: () => _playEpisode(_prevRef!),
                      )
                    : IconButton(
                        iconSize: 34,
                        onPressed: _prevRef != null
                            ? () => _playEpisode(_prevRef!)
                            : null,
                        icon: const Icon(Icons.skip_previous),
                        color: Colors.white,
                        disabledColor: Colors.white24,
                        tooltip: 'Previous episode',
                      ),
              const SizedBox(width: 12),
              _tizenWeb
                  ? _TvIconButton(
                      icon: Icons.replay,
                      label: '15',
                      focusNode: _rewFocus,
                      onTap: () => _seekBy(-15000),
                    )
                  : _RoundBtn(
                      icon: Icons.replay,
                      label: '15',
                      onTap: () => _seekBy(-15000),
                    ),
              const SizedBox(width: 20),
              _tizenWeb
                  ? _TvIconButton(
                      icon: _playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      iconSize: 64,
                      focusNode: _playPauseFocus,
                      autofocus: true,
                      onTap: _togglePlay,
                    )
                  : IconButton(
                      iconSize: 64,
                      onPressed: _togglePlay,
                      icon: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                    ),
              const SizedBox(width: 20),
              _tizenWeb
                  ? _TvIconButton(
                      icon: Icons.replay,
                      label: '15',
                      flip: true,
                      focusNode: _ffFocus,
                      onTap: () => _seekBy(15000),
                    )
                  : _RoundBtn(
                      icon: Icons.replay,
                      label: '15',
                      flip: true,
                      onTap: () => _seekBy(15000),
                    ),
              const SizedBox(width: 12),
              if (_isTv && (!_tizenWeb || _nextRef != null))
                _tizenWeb
                    ? _TvIconButton(
                        icon: Icons.skip_next,
                        focusNode: _nextFocus,
                        onTap: () => _playEpisode(_nextRef!),
                      )
                    : IconButton(
                        iconSize: 34,
                        onPressed: _nextRef != null
                            ? () => _playEpisode(_nextRef!)
                            : null,
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
                Text(_fmt(_scrubbing ? _scrubPreviewMs : _positionMs),
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(width: 10),
                Expanded(
                  child: _tizenWeb
                      ? _TvSeekBar(
                          positionMs:
                              _scrubbing ? _scrubPreviewMs : _positionMs,
                          durationMs: _durationMs,
                          buffered: _bufferedFraction,
                          focusNode: _seekFocus,
                          scrubbing: _scrubbing,
                          onEnterScrub: _enterScrub,
                          onCommitScrub: _commitScrub,
                          onCancelScrub: _cancelScrub,
                          onSeekStep: _scrubStep,
                          onSeekTo: _seekToMs,
                        )
                      : _seekBar(),
                ),
                const SizedBox(width: 10),
                Text(_fmt(_durationMs),
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                _tizenWeb
                    ? _TvIconButton(
                        icon: Icons.graphic_eq,
                        focusNode: _soundFocus,
                        color: _soundMode == SoundMode.off
                            ? Colors.white70
                            : Colors.white,
                        onTap: _showSoundMenu,
                      )
                    : IconButton(
                        onPressed: _showSoundMenu,
                        tooltip: _soundMode == SoundMode.off
                            ? 'Sound'
                            : 'Sound: ${_soundMode.label}',
                        icon: Icon(
                          Icons.graphic_eq,
                          color: _soundMode == SoundMode.off
                              ? Colors.white70
                              : Colors.white,
                        ),
                      ),
                if (hasQuality) ...[
                  const SizedBox(width: 4),
                  _tizenWeb
                      ? _TvIconButton(
                          icon: Icons.high_quality_outlined,
                          focusNode: _qualityFocus,
                          onTap: _showQualityMenu,
                        )
                      : IconButton(
                          onPressed: _showQualityMenu,
                          tooltip: 'Quality',
                          icon: const Icon(Icons.high_quality_outlined,
                              color: Colors.white),
                        ),
                ],
                _tizenWeb
                    ? _TvIconButton(
                        icon: _subIndex < 0
                            ? Icons.closed_caption_off_outlined
                            : Icons.closed_caption,
                        focusNode: _subFocus,
                        color:
                            _subIndex < 0 ? Colors.white70 : Colors.white,
                        onTap: _showSubtitleMenu,
                      )
                    : IconButton(
                        onPressed: _showSubtitleMenu,
                        tooltip: _subIndex < 0
                            ? 'Subtitles'
                            : 'Subtitles: ${_subs[_subIndex].label}',
                        icon: Icon(
                          _subIndex < 0
                              ? Icons.closed_caption_off_outlined
                              : Icons.closed_caption,
                          color:
                              _subIndex < 0 ? Colors.white70 : Colors.white,
                        ),
                      ),
                _tizenWeb
                    ? _TvIconButton(
                        icon: _fullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        focusNode: _fullFocus,
                        onTap: _toggleFullscreen,
                      )
                    : IconButton(
                        onPressed: _toggleFullscreen,
                        tooltip:
                            _fullscreen ? 'Exit full screen' : 'Full screen',
                        icon: Icon(
                          _fullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
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
  const _SkipButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.focusNode,
    this.autofocus = true,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<_SkipButton> createState() => _SkipButtonState();
}

class _SkipButtonState extends State<_SkipButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
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

/// Subtitle list, upload, search, and manual timing. Pops the chosen row.
class _SubtitleMenu extends StatefulWidget {
  const _SubtitleMenu({
    required this.labels,
    required this.current,
    required this.offsetMs,
    required this.onOffset,
    required this.onUpload,
    required this.onSearch,
  });
  final List<String> labels;
  final int current;
  final int offsetMs;
  final ValueChanged<int> onOffset;
  final Future<bool> Function() onUpload;
  final Future<bool> Function() onSearch;

  @override
  State<_SubtitleMenu> createState() => _SubtitleMenuState();
}

class _SubtitleMenuState extends State<_SubtitleMenu> {
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
                _MenuRow(
                  label: 'Search SRT',
                  selected: false,
                  onTap: () async {
                    final added = await widget.onSearch();
                    if (added && context.mounted) Navigator.pop(context);
                  },
                ),
                const Divider(height: 1, color: Colors.white24),
                SubtitleTimingControls(
                  offsetMs: widget.offsetMs,
                  onChanged: widget.onOffset,
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
  const _PickerMenu({
    required this.title,
    required this.labels,
    required this.current,
    this.details,
    this.onSelected,
  });
  final String title;
  final List<String> labels;
  final int current;
  final List<String>? details;

  /// Runs in the tap, before the dialog closes, so a browser user-gesture
  /// (needed to start the sound booster) is still active.
  final ValueChanged<int>? onSelected;

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
                          detail: details != null && i < details!.length
                              ? details![i]
                              : null,
                          selected: i == current,
                          autofocus: i == current,
                          onTap: () {
                            onSelected?.call(i);
                            Navigator.pop(context, i);
                          },
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
  const _MenuRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
    this.autofocus = false,
  });
  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = {
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.gameButtonA,
      LogicalKeyboardKey.mediaPlayPause,
    };
    if (!keys.contains(event.logicalKey)) return KeyEventResult.ignored;
    widget.onTap();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: _focused ? Colors.white24 : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: widget.selected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    if (widget.detail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          widget.detail!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
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

/// White focus ring, same idea as the Android player's remote buttons.
class _TvIconButton extends StatefulWidget {
  const _TvIconButton({
    required this.icon,
    required this.onTap,
    this.iconSize = 34,
    this.focusNode,
    this.autofocus = false,
    this.label,
    this.flip = false,
    this.color = Colors.white,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double iconSize;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? label;
  final bool flip;
  final Color color;

  @override
  State<_TvIconButton> createState() => _TvIconButtonState();
}

class _TvIconButtonState extends State<_TvIconButton> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = {
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.gameButtonA,
      LogicalKeyboardKey.mediaPlayPause,
    };
    if (!keys.contains(event.logicalKey)) return KeyEventResult.ignored;
    widget.onTap();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    Widget icon = Icon(widget.icon, color: widget.color, size: widget.iconSize);
    if (widget.flip) icon = Transform.flip(flipX: true, child: icon);
    if (widget.label != null) {
      icon = Stack(
        alignment: Alignment.center,
        children: [
          icon,
          Text(
            widget.label!,
            style: TextStyle(
              color: widget.color,
              fontSize: widget.iconSize * 0.28,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ],
      );
    }
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _focused ? 1.12 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _focused ? Colors.white : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: icon,
          ),
        ),
      ),
    );
  }
}

/// Timeline. Arrows move to the neighboring controls until Select starts
/// scrubbing; then Left/Right move the marker and Select applies it.
class _TvSeekBar extends StatefulWidget {
  const _TvSeekBar({
    required this.positionMs,
    required this.durationMs,
    required this.buffered,
    required this.focusNode,
    required this.scrubbing,
    required this.onEnterScrub,
    required this.onCommitScrub,
    required this.onCancelScrub,
    required this.onSeekStep,
    required this.onSeekTo,
  });

  final int positionMs;
  final int durationMs;
  final double buffered;
  final FocusNode focusNode;
  final bool scrubbing;
  final VoidCallback onEnterScrub;
  final VoidCallback onCommitScrub;
  final VoidCallback onCancelScrub;
  final void Function(int deltaMs) onSeekStep;
  final void Function(int ms) onSeekTo;

  @override
  State<_TvSeekBar> createState() => _TvSeekBarState();
}

class _TvSeekBarState extends State<_TvSeekBar> {
  bool _focused = false;

  static const _stepMs = 15000;

  static final _selectKeys = {
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.gameButtonA,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final down = event is KeyDownEvent;
    final repeat = event is KeyRepeatEvent;
    if (!down && !repeat) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (widget.scrubbing) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        widget.onSeekStep(-_stepMs);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        widget.onSeekStep(_stepMs);
        return KeyEventResult.handled;
      }
      if (down &&
          (_selectKeys.contains(key) ||
              key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown)) {
        widget.onCommitScrub();
        return KeyEventResult.handled;
      }
      if (down &&
          (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack)) {
        widget.onCancelScrub();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }
    if (down && _selectKeys.contains(key)) {
      widget.onEnterScrub();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final dur = widget.durationMs;
    final frac = dur > 0 ? (widget.positionMs / dur).clamp(0.0, 1.0) : 0.0;
    final active = _focused || widget.scrubbing;
    final barHeight = active ? 6.0 : 3.0;
    final accent = widget.scrubbing ? AppColors.ratingYellow : Colors.white;
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      onFocusChange: (f) => setState(() => _focused = f),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          if (dur <= 0) return;
          final box = context.findRenderObject() as RenderBox?;
          if (box == null || box.size.width <= 0) return;
          widget.focusNode.requestFocus();
          final dx = d.localPosition.dx.clamp(0.0, box.size.width);
          widget.onSeekTo((dx / box.size.width * dur).round());
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              return Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Container(
                    width: w * widget.buffered.clamp(0.0, 1.0),
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: Colors.white54,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Container(
                    width: w * frac,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  if (active)
                    Positioned(
                      left: (w * frac) - 9,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent,
                          border: Border.all(color: Colors.black54, width: 1),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

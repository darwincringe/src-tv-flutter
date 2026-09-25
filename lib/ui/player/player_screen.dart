import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme.dart';
import '../../data/introdb/introdb_client.dart';
import '../../data/models/details_dto.dart';
import '../../data/repository/media_repository.dart';
import '../../data/store/active_playback.dart';
import '../../data/store/subtitle_pref.dart';
import '../../data/store/watch_progress.dart';
import '../../data/tmdb/image_urls.dart';
import '../../data/youtube/youtube_extractor.dart';
import 'player_args.dart';
import 'subtitle_config.dart';
import 'subtitle_parser.dart';

class _EpisodeRef {
  final int season;
  final int episode;
  const _EpisodeRef(this.season, this.episode);
}

/// Video player built on better_player_plus (ExoPlayer/AVPlayer). ExoPlayer
/// renders through a Surface, so playback is smooth even where a texture-based
/// player struggles. Custom overlay controls give clear D-pad focus.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.args});
  final PlayerArgs args;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  static const int _maxRetries = 4;
  static const int _seekStepMs = 15000;
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Safari/537.36';

  BetterPlayerController? _controller;
  Timer? _tick;
  Timer? _hideTimer;
  int _ticks = 0;

  // Playback target (mutable so we can advance episodes).
  late PlayerMode _mode;
  late int _tmdbId;
  late String _type;
  int? _season;
  int? _episode;
  String? _trailerKey;

  // Loaded metadata
  String? _mediaTitle;
  String? _episodeName;
  String? _posterPath;
  String? _backdropPath; // shown on the loading screen (hero-style)
  // The current episode's still image — preferred on the loading screen for TV
  // episodes (so each episode shows its own banner), falling back to the series
  // backdrop when the episode has no still.
  String? _episodeStillPath;
  // Keep the loading banner+spinner up until at least this epoch-ms. Set when
  // jumping to another episode (Next/Prev) so the new episode's banner is
  // actually visible even when it buffers in well under a second.
  int _minLoaderUntilMs = 0;
  bool _isTv = false;

  // Loading-screen progress (0..100), animated up while buffering.
  double _loadProgress = 0;
  Timer? _loadTimer;
  List<Season> _seasons = [];
  _EpisodeRef? _nextRef;
  _EpisodeRef? _prevRef;

  // Streaming state
  final List<SubtitleOption> _uploadedSubs = [];
  List<SubtitleOption> _subOptions = []; // all current subtitle options
  // We fetch + parse subtitles ourselves (see subtitle_parser.dart) and render
  // them in our own overlay, so better_player never parses them.
  List<SubtitleCue> _cues = [];
  int _activeSubIndex = -1; // index into _subOptions; -1 = off
  int _subLoadToken = 0; // guards against a stale async load winning
  int _resumeTargetMs = 0;
  bool _resumeDone = true;
  int _resumeSeekAtMs = 0; // when the resume seek was issued (reveal fallback)
  int _retryCount = 0;

  // UI state
  bool _loading = true;
  // A mid-playback rebuffer (distinct from the initial load). Shows the episode
  // banner + spinner + "Buffering", covering the frozen frame; ExoPlayer holds
  // playback until it has buffered a stable amount, then auto-resumes.
  bool _buffering = false;
  Timer? _bufferDebounce; // ignore momentary buffer blips before showing it
  String? _errorMsg;
  bool _showControls = true;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  // How far the stream is buffered ahead (0..1 of the duration), shown as a
  // lighter track behind the played portion of the seek bar.
  double _bufferedFraction = 0;

  // Recap/intro/outro timings (introdb) for the current TV episode, and the
  // currently-applicable action ('recap' | 'intro' | 'next' | null) which
  // drives the Skip Recap / Skip Intro / Next Episode button.
  MediaSegments? _segments;
  String? _actionKind;
  bool _autoHideArmed = false; // controls auto-hide armed once playback begins

  // TV / D-pad control state.
  // A scope (not a plain Focus) so that if a focused control is rebuilt away,
  // focus falls back HERE — letting us catch the next key and recover instead
  // of stranding focus somewhere the remote can't drive.
  final FocusScopeNode _rootScope = FocusScopeNode(debugLabel: 'playerRoot');
  final FocusNode _playPauseFocus = FocusNode(debugLabel: 'playpause');
  final FocusNode _seekFocus = FocusNode(debugLabel: 'seek');
  final FocusNode _skipFocus = FocusNode(debugLabel: 'skip');
  bool _scrubbing = false; // seek-bar "scrub mode" active
  int _scrubPreviewMs = 0; // marker position while scrubbing (not yet applied)
  bool _wasPlayingBeforeScrub = false;
  bool _leaving = false; // user confirmed exit — suppress lifecycle re-saves
  bool _disposed = false; // set in dispose — suppress late events/setState
  bool _backgrounded = false; // app not foregrounded — never let audio play
  String? _subtitleText; // current subtitle, rendered by our own overlay

  int get _now => DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    PlayerRuntime.isOpen = true;
    WidgetsBinding.instance.addObserver(this);

    final a = widget.args;
    _mode = a.mode;
    _tmdbId = a.tmdbId ?? 0;
    _type = a.type ?? 'movie';
    _season = a.season;
    _episode = a.episode;
    _trailerKey = a.trailerKey;
    _backdropPath = a.backdropPath; // show it on the loader immediately (0%)

    _resolveAndPlay();
  }

  BetterPlayerController _buildController() {
    return BetterPlayerController(
      BetterPlayerConfiguration(
        fit: BoxFit.contain,
        // autoPlay MUST stay false: with autoPlay:true, backing out while the
        // HLS source is still preparing lets better_player start playback on its
        // own when setup finishes (a few seconds later) — audio playing on a
        // screen the user already left. We start playback ourselves, only from
        // the initialized handler / tick, which both bail when _disposed.
        autoPlay: false,
        handleLifecycle: false,
        autoDispose: false,
        expandToFill: true,
        errorBuilder: (context, msg) => const SizedBox.shrink(),
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          showControls: false,
        ),
        // better_player's caption renderer can't do bold + soft shadow, so we
        // hide it (transparent) and draw our own Netflix-style subtitle overlay.
        subtitlesConfiguration: const BetterPlayerSubtitlesConfiguration(
          fontSize: 1,
          fontColor: Color(0x00000000),
          outlineEnabled: false,
          backgroundColor: Color(0x00000000),
        ),
        eventListener: _onEvent,
      ),
    );
  }

  void _onEvent(BetterPlayerEvent event) {
    // Disposing the controller emits final events synchronously; ignore them so
    // we never setState on a defunct element (mounted can still be true here).
    if (_disposed) return;
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        _retryCount = 0;
        // Keep muted while a resume seek is still pending (see _resolveStream).
        if (_resumeTargetMs > 0 && !_resumeDone) {
          _controller?.setVolume(0);
        }
        // Don't seek here — seeking right after init stalls ExoPlayer. The
        // resume seek is applied from the tick once playback is advancing.
        // Hold on the loading banner (paused, but still buffering, so no audio
        // plays behind it) until the minimum banner time has passed. The tick
        // starts playback and lifts the loader once we're past that time and,
        // if resuming, the seek has landed.
        //
        // Exception: when resuming, we must start playback now (muted) even
        // inside the banner window — the resume seek only fires once the
        // position is advancing, so a paused player would sit at 0 forever.
        if (_now < _minLoaderUntilMs && _resumeTargetMs <= 0) {
          _controller?.pause();
        } else {
          _controller?.play();
          // If resuming, KEEP the loader up until the seek lands (so the
          // opening never plays on screen — seamless resume). Otherwise lift.
          if (_resumeTargetMs <= 0) {
            // Not resuming: make sure audio is on (the controller is reused
            // across episodes and could be left muted by a prior resume).
            _controller?.setVolume(1.0);
            _loadTimer?.cancel();
            if (mounted) setState(() => _loading = false);
          }
        }
        _startTick();
        break;
      case BetterPlayerEventType.play:
        _playing = true;
        WakelockPlus.enable();
        // Arm the auto-hide countdown ONCE when playback first begins (not on
        // every play event — buffering fires repeated plays that would keep
        // resetting it and the controls would never fade).
        if (!_autoHideArmed) {
          _autoHideArmed = true;
          _restartHideTimer();
        }
        if (mounted) setState(() {});
        break;
      case BetterPlayerEventType.pause:
        _playing = false;
        WakelockPlus.disable();
        if (mounted) setState(() {});
        break;
      case BetterPlayerEventType.finished:
        _onCompleted();
        break;
      case BetterPlayerEventType.bufferingStart:
        // A rebuffer mid-playback (not the initial load, which _loading covers).
        // Debounced so a momentary blip doesn't flash the overlay.
        if (!_loading && !_disposed) {
          _bufferDebounce?.cancel();
          _bufferDebounce = Timer(const Duration(milliseconds: 400), () {
            if (mounted && !_loading && !_disposed) {
              setState(() => _buffering = true);
            }
          });
        }
        break;
      case BetterPlayerEventType.bufferingEnd:
        // Enough is buffered to play smoothly — hide the banner; ExoPlayer
        // resumes on its own (STATE_READY).
        _bufferDebounce?.cancel();
        if (_buffering && mounted) setState(() => _buffering = false);
        break;
      case BetterPlayerEventType.exception:
        _retryOrError('Playback error');
        break;
      default:
        break;
    }
  }

  // ---- Resolve + play ----------------------------------------------------

  // Animate the loading % up while buffering (eases toward ~96% and stops; the
  // real buffered fraction isn't reliably available before init on ExoPlayer).
  void _startLoadProgress() {
    _loadProgress = 0;
    _loadTimer?.cancel();
    _loadTimer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      if (!mounted || !_loading) {
        _loadTimer?.cancel();
        return;
      }
      setState(() {
        _loadProgress += (96 - _loadProgress) * 0.10;
        if (_loadProgress > 96) _loadProgress = 96;
      });
    });
  }

  Future<void> _resolveAndPlay() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    _startLoadProgress();
    if (_mode == PlayerMode.trailer) {
      await _resolveTrailer();
    } else {
      await _resolveStream();
    }
  }

  Future<void> _resolveTrailer() async {
    final key = _trailerKey;
    if (key == null) {
      _retryOrError('Trailer unavailable');
      return;
    }
    try {
      final sources = await YouTubeExtractor.streamsFor(key);
      if (sources == null) {
        _retryOrError('Trailer unavailable');
        return;
      }
      _controller ??= _buildController();
      await _controller!.setupDataSource(
        BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          sources.videoUrl,
        ),
      );
    } catch (_) {
      _retryOrError('Trailer unavailable');
    }
  }

  Future<void> _resolveStream() async {
    if (_disposed) return;
    try {
      final repo = ref.read(mediaRepositoryProvider);
      final res = await repo.streamSource(
        _type,
        _tmdbId,
        season: _season,
        episode: _episode,
      );
      if (!res.success || (res.hlsUrl?.isEmpty ?? true)) {
        _retryOrError(res.error ?? 'No playable source found');
        return;
      }

      if (_mediaTitle == null) {
        try {
          final d = await repo.details(_type, _tmdbId);
          _mediaTitle = d.title;
          _posterPath = d.posterPath;
          _backdropPath = d.backdropPath;
          _isTv = d.isTv;
          _seasons = d.seasons;
          if (mounted) setState(() {}); // show the backdrop on the loader
        } catch (_) {}
      }
      if (_type == 'tv' && _episode != null) {
        try {
          final eps = await repo.episodes(_tmdbId, _season ?? 1);
          final match = eps.where((e) => e.episodeNumber == _episode);
          _episodeName = match.isNotEmpty ? match.first.name : null;
          // Prefer this episode's own still on the loading screen.
          _episodeStillPath = match.isNotEmpty ? match.first.stillPath : null;
          if (mounted) setState(() {}); // swap the loader to the episode banner
        } catch (_) {
          _episodeName = null;
        }
      }
      _computeEpisodeRefs();
      if (_type == 'tv' && _season != null && _episode != null) {
        _fetchSegments(_season!, _episode!);
      }
      _resumeTargetMs = _savedResumePosition();
      _resumeDone = _resumeTargetMs <= 0;

      _setupSubtitles(res.subtitles);
      _controller ??= _buildController();
      await _controller!.setupDataSource(
        BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          res.hlsUrl!,
          videoFormat: BetterPlayerVideoFormat.hls,
          headers: const {'User-Agent': _userAgent},
          // Subtitles are handled entirely by us (fetch + parse + render), not
          // by better_player — its SRT parser crashes on 3+ line cues.
          useAsmsSubtitles: false,
          useAsmsTracks: true,
          // Buffer far ahead (target ~10 min) so a shaky source (e.g. The
          // Office S4E8) rides through stalls; after a rebuffer, wait for a
          // solid ~12s cushion before resuming so it doesn't immediately stall
          // again. The time target is bounded by an 80 MB byte cap in the
          // vendored player's LoadControl (see BetterPlayer.kt) because the
          // buffer lives in the Java heap and would otherwise OOM the box: full
          // 10 min at lower bitrates, ~2 min at 1080p, whichever hits 80 MB.
          bufferingConfiguration: const BetterPlayerBufferingConfiguration(
            minBufferMs: 120000,
            maxBufferMs: 600000,
            bufferForPlaybackMs: 3000,
            bufferForPlaybackAfterRebufferMs: 12000,
          ),
        ),
      );
      // If the user backed out while the source was still preparing, tear the
      // controller down here and don't start anything — otherwise it would sit
      // ready and (previously) auto-play on a screen that no longer exists.
      if (_disposed) {
        _controller?.pause();
        _controller?.dispose(forceDispose: true);
        return;
      }
      // Seamless resume: silence playback from the very start so the opening
      // that would otherwise play before the tick seeks to the saved position is
      // never heard (the loader already hides the video). Unmuted the instant
      // the seek lands on the resume point.
      if (_resumeTargetMs > 0) {
        await _controller?.setVolume(0);
      }
    } catch (_) {
      _retryOrError('Playback error');
    }
  }

  void _retryOrError(String message) {
    if (_retryCount >= _maxRetries) {
      if (mounted) {
        setState(() {
          _errorMsg = message;
          _loading = false;
        });
      }
      return;
    }
    _retryCount++;
    if (mounted) setState(() => _loading = true);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) _resolveAndPlay();
    });
  }

  int _savedResumePosition() {
    final p = WatchProgressStore.get(_type, _tmdbId);
    if (p == null || !p.isResumable) return 0;
    if (_type == 'tv' && (p.season != _season || p.episode != _episode)) {
      return 0;
    }
    return p.positionMs;
  }

  // ---- Subtitles ---------------------------------------------------------

  void _setupSubtitles(List<String> apiUrls) {
    _subOptions = [
      ...apiSubtitleOptions(apiUrls),
      ..._uploadedSubs,
    ];
    _selectSubtitle(_defaultSubtitleIndex(_subOptions), remember: false);
  }

  /// Selects a subtitle track (or -1 for Off), remembers the choice, and loads
  /// its cues in the background. Guarded by a token so switching tracks quickly
  /// never lets a slow earlier load overwrite a newer one.
  Future<void> _selectSubtitle(int index, {bool remember = true}) async {
    _activeSubIndex = index;
    final token = ++_subLoadToken;
    if (index < 0) {
      if (mounted) setState(() => _cues = []);
      if (remember) {
        await SubtitlePrefStore.save(
            _type, _tmdbId, _season, const SubtitlePref(off: true));
      }
      return;
    }
    if (index >= _subOptions.length) return;
    final opt = _subOptions[index];
    if (remember) {
      await SubtitlePrefStore.save(
          _type,
          _tmdbId,
          _season,
          SubtitlePref(name: opt.label, language: subtitlePrefLanguage(opt)));
    }
    // The subtitle host (OpenSubtitles) intermittently rate-limits back-to-back
    // requests — especially right after auto-advancing an episode — so a single
    // fetch can come back empty. Retry a couple of times before giving up, which
    // is why manually re-selecting "just worked" before.
    var cues = await loadSubtitleCues(opt.uri, userAgent: _userAgent);
    for (var attempt = 0; cues.isEmpty && attempt < 2; attempt++) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted || token != _subLoadToken) return;
      cues = await loadSubtitleCues(opt.uri, userAgent: _userAgent);
    }
    if (!mounted || token != _subLoadToken) return;
    setState(() => _cues = cues);
    if (cues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load that subtitle')),
      );
    }
  }

  /// Chooses the default subtitle: the remembered choice (matched by name, then
  /// language), else English (case-insensitive), else the first track. Returns
  /// -1 if the user previously turned subtitles off.
  int _defaultSubtitleIndex(List<SubtitleOption> opts) {
    final remembered = rememberedSubtitleIndex(
      opts,
      SubtitlePrefStore.get(_type, _tmdbId, _season),
    );
    if (remembered != null) return remembered;
    final en = opts.indexWhere((o) {
      final lang = (o.language ?? '').toLowerCase();
      final label = o.label.toLowerCase();
      return lang == 'en' ||
          lang.contains('eng') ||
          label.contains('eng') ||
          label.contains('english');
    });
    if (en >= 0) return en;
    return opts.isNotEmpty ? 0 : -1;
  }

  Future<void> _uploadSubtitle() async {
    const group = XTypeGroup(
      label: 'subtitles',
      extensions: ['srt', 'vtt', 'ass', 'ssa'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    final opt = uploadedSubtitleOption(file.path, _uploadedSubs.length);
    _uploadedSubs.add(opt);
    setState(() => _subOptions = [..._subOptions, opt]);
    await _selectSubtitle(_subOptions.length - 1);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subtitle added')),
      );
    }
  }

  void _showSubtitleDialog() {
    if (_subOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No subtitles available')),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.charcoalLight,
        title: const Text('Subtitles',
            style: TextStyle(color: AppColors.textPrimary)),
        children: [
          _dialogOption(ctx, 'Off', _activeSubIndex < 0,
              () => _selectSubtitle(-1)),
          for (var i = 0; i < _subOptions.length; i++)
            _dialogOption(ctx, _subOptions[i].label, i == _activeSubIndex,
                () => _selectSubtitle(i)),
        ],
      ),
    );
  }

  // ---- Quality -----------------------------------------------------------

  void _showQualityDialog() {
    final controller = _controller;
    if (controller == null) return;
    final tracks = <BetterPlayerAsmsTrack>[];
    final seen = <int>{};
    for (final t in controller.betterPlayerAsmsTracks) {
      final h = t.height ?? 0;
      if (h <= 0) continue;
      if (seen.add(h)) tracks.add(t);
    }
    tracks.sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only one quality available')),
      );
      return;
    }
    final currentHeight = controller.betterPlayerAsmsTrack?.height ?? 0;
    final isAuto = currentHeight <= 0;
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.charcoalLight,
        title: const Text('Quality',
            style: TextStyle(color: AppColors.textPrimary)),
        children: [
          _dialogOption(ctx, 'Auto', isAuto,
              () => controller.setTrack(BetterPlayerAsmsTrack.defaultTrack())),
          for (final t in tracks)
            _dialogOption(ctx, '${t.height}p',
                !isAuto && currentHeight == t.height,
                () => controller.setTrack(t)),
        ],
      ),
    );
  }

  Widget _dialogOption(
    BuildContext ctx,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return _DialogOption(
      label: label,
      selected: selected,
      autofocus: selected, // land D-pad focus on the current choice
      onTap: () {
        onTap();
        Navigator.pop(ctx);
      },
    );
  }

  // ---- Episodes ----------------------------------------------------------

  int _episodeCount(int season) {
    for (final s in _seasons) {
      if (s.seasonNumber == season) return s.episodeCount ?? 0;
    }
    return 0;
  }

  void _computeEpisodeRefs() {
    _nextRef = null;
    _prevRef = null;
    if (!(_type == 'tv' && _season != null && _episode != null)) return;
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
        _prevRef =
            _EpisodeRef(earlier.first.seasonNumber, earlier.first.episodeCount ?? 1);
      }
    }
  }

  void _playEpisode(_EpisodeRef ref) {
    // Pause the current episode straight away so it doesn't keep playing (audio
    // + video) behind the loading spinner while the next one is resolved.
    _controller?.pause();
    setState(() {
      _season = ref.season;
      _episode = ref.episode;
      _episodeName = null;
      // Show the loading screen right away (over the paused last frame) and
      // drop the previous episode's still so we don't show its banner for the
      // new one — the series backdrop shows until the new still is fetched.
      _loading = true;
      _loadProgress = 0;
      _episodeStillPath = null;
      // Hold the banner + spinner for at least 5s so it's clearly "loading the
      // next episode" instead of the button flashing straight into playback.
      _minLoaderUntilMs = _now + 5000;
      _retryCount = 0;
      _cues = []; // drop the previous episode's subtitles immediately
      _segments = null; // and its recap/intro/outro timings
      _actionKind = null;
      _autoHideArmed = false; // re-arm auto-hide for the new episode
    });
    _resolveAndPlay();
  }

  Future<void> _fetchSegments(int season, int episode) async {
    try {
      final seg = await ref
          .read(mediaRepositoryProvider)
          .episodeSegments(_tmdbId, season, episode);
      if (!mounted || _season != season || _episode != episode) return;
      setState(() => _segments = seg);
    } catch (_) {}
  }

  void _seekToMs(int ms) {
    _controller?.seekTo(Duration(milliseconds: ms));
    _controller?.play();
    _restartHideTimer();
  }

  static final _activateKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.gameButtonA,
  };

  bool _isActivateKey(LogicalKeyboardKey k) => _activateKeys.contains(k);

  // ---- Progress ----------------------------------------------------------

  void _startTick() {
    _tick?.cancel();
    _ticks = 0;
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final v = _controller?.videoPlayerController?.value;
      if (v == null || !v.initialized) return;
      _position = v.position;
      _duration = v.duration ?? Duration.zero;
      // Furthest buffered point (across ranges) as a fraction of the duration.
      final durMs0 = _duration.inMilliseconds;
      if (durMs0 > 0 && v.buffered.isNotEmpty) {
        final endMs = v.buffered
            .map((r) => r.end.inMilliseconds)
            .reduce((a, b) => a > b ? a : b);
        _bufferedFraction = (endMs / durMs0).clamp(0.0, 1.0);
      } else {
        _bufferedFraction = 0;
      }
      // Skip all auto-play while backgrounded so a video never starts (or
      // resumes) audio when the app isn't on screen. Deferred to the next tick
      // once foregrounded.
      if (!_backgrounded) {
        // Apply the resume seek only once playback is genuinely advancing;
        // seeking earlier (on init) stalls ExoPlayer. This is the same path as
        // a manual seek, which works reliably.
        if (!_resumeDone &&
            _resumeTargetMs > 0 &&
            _position.inMilliseconds >= 800) {
          _resumeDone = true;
          _resumeSeekAtMs = _now;
          _controller?.seekTo(Duration(milliseconds: _resumeTargetMs));
          _controller?.play();
        }
        // Keep the loader up during a resume until playback has actually
        // ADVANCED past the saved position — not merely until the seek is
        // requested. `position` jumps to the target the instant seekTo is
        // called, but the decoded frame on screen is still the opening until
        // the target HLS segment loads; revealing then flashes the beginning.
        // Waiting for position > target proves the target frame is live. A 6s
        // fallback avoids a stuck loader if position reporting misbehaves.
        if (_loading && _resumeDone) {
          final landed = _resumeTargetMs <= 0 ||
              _position.inMilliseconds >= _resumeTargetMs + 250 ||
              (_resumeSeekAtMs > 0 && _now - _resumeSeekAtMs > 6000);
          if (landed && _now >= _minLoaderUntilMs) {
            _loadTimer?.cancel();
            // We're now sitting on the resume point with the video about to be
            // revealed — restore audio (muted since setup) so sound and picture
            // start together, then play and lift the loader.
            _controller?.setVolume(1.0);
            _controller?.play(); // start playback we held during the min window
            if (mounted) setState(() => _loading = false);
          }
        }
      }
      final action = _computeActionKind();
      final actionChanged = action != _actionKind;
      if (actionChanged) {
        _actionKind = action;
        // When a Skip/Next button appears, focus it so the remote OK skips
        // straight away (rather than revealing the controls).
        if (action != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _actionKind != null && _skipFocus.canRequestFocus) {
              _skipFocus.requestFocus();
            }
          });
        }
      }
      final sub = _currentSubtitleText();
      final subChanged = sub != _subtitleText;
      if (subChanged) _subtitleText = sub;
      _ticks++;
      if (_ticks % 60 == 0) _saveProgress(); // every 30s
      if (mounted && (_showControls || subChanged || actionChanged)) {
        setState(() {});
      }
    });
  }

  /// Current subtitle text for the active track, from our own parsed cues at
  /// the current position (rendered by us for a bold/shadow Netflix look).
  String? _currentSubtitleText() {
    if (_cues.isEmpty) return null;
    final pos = _position;
    for (final c in _cues) {
      if (pos >= c.start && pos <= c.end) {
        final t = c.text.trim();
        return t.isEmpty ? null : t;
      }
    }
    return null;
  }

  /// Which contextual button applies at the current position: a recap/intro to
  /// skip (from introdb), or the outro → Next Episode. Falls back to the last
  /// 5% of the episode for Next Episode when introdb has no outro.
  String? _computeActionKind() {
    if (_mode != PlayerMode.stream) return null;
    final posMs = _position.inMilliseconds;
    final dur = _duration.inMilliseconds;
    final seg = _segments;
    // Trust an introdb outro only if it lands in the back half of the runtime —
    // some crowd-sourced entries have a bogus early outro that would otherwise
    // pop "Next Episode" during the opening.
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
    if (_isTv &&
        _nextRef != null &&
        dur > 0 &&
        posMs >= dur * 0.95 &&
        !outroValid) {
      return 'next';
    }
    return null;
  }

  /// The position at which the title counts as "finished". For episodes with
  /// introdb data this is the outro start (the credits); otherwise — and always
  /// for movies — it's 95% of the runtime.
  int _completionThresholdMs() {
    final dur = _duration.inMilliseconds;
    final outro = _segments?.outro;
    if (_isTv && outro != null && (dur <= 0 || outro.startMs > dur * 0.5)) {
      return outro.startMs;
    }
    return (dur * 0.95).round();
  }

  void _saveProgress() {
    if (_mode != PlayerMode.stream) return;
    if (!_resumeDone) return;
    final pos = _position.inMilliseconds;
    final dur = _duration.inMilliseconds;
    if (dur <= 0) return;
    // If we're already at/after the credits (the "Next Episode" affordance is
    // showing, or we've passed the completion point), treat the episode as done
    // so resuming later starts the NEXT episode — not this one from the top.
    if (_actionKind == 'next' || pos >= _completionThresholdMs()) {
      _markReachedEnd();
      return;
    }
    WatchProgressStore.save(WatchProgress(
      tmdbId: _tmdbId,
      type: _type,
      season: _season,
      episode: _episode,
      positionMs: pos,
      durationMs: dur,
      updatedAt: _now,
      title: _mediaTitle,
      posterPath: _posterPath,
      completed: false,
    ));
  }

  void _markReachedEnd() {
    if (_isTv && _nextRef != null) {
      WatchProgressStore.save(WatchProgress(
        tmdbId: _tmdbId,
        type: 'tv',
        season: _nextRef!.season,
        episode: _nextRef!.episode,
        positionMs: 0,
        durationMs: 0,
        updatedAt: _now,
        title: _mediaTitle,
        posterPath: _posterPath,
        completed: false,
      ));
    } else {
      final dur = _duration.inMilliseconds;
      WatchProgressStore.save(WatchProgress(
        tmdbId: _tmdbId,
        type: _type,
        season: _season,
        episode: _episode,
        positionMs: dur,
        durationMs: dur,
        updatedAt: _now,
        title: _mediaTitle,
        posterPath: _posterPath,
        completed: true,
      ));
    }
  }

  void _onCompleted() {
    if (_mode != PlayerMode.stream) return;
    _markReachedEnd();
    if (_isTv && _nextRef != null) _playEpisode(_nextRef!);
  }

  // ---- Controls / seek ---------------------------------------------------

  void _seekBy(int deltaMs) {
    final dur = _duration.inMilliseconds;
    var target = _position.inMilliseconds + deltaMs;
    if (target < 0) target = 0;
    if (dur > 0 && target > dur) target = dur;
    _controller?.seekTo(Duration(milliseconds: target));
    _controller?.play(); // avoid post-seek stall
  }

  void _togglePlay() {
    if (_playing) {
      _controller?.pause();
    } else {
      _controller?.play();
    }
  }

  // ---- Scrub mode (seek bar) ---------------------------------------------

  void _enterScrub() {
    _scrubPreviewMs = _position.inMilliseconds;
    _wasPlayingBeforeScrub = _playing;
    _controller?.pause(); // pause while scrubbing
    setState(() => _scrubbing = true);
    _restartHideTimer();
  }

  // Only moves the marker — does NOT seek the video, so holding slides smoothly
  // without the stream re-buffering at every step.
  void _scrubStep(int deltaMs) {
    final dur = _duration.inMilliseconds;
    var t = _scrubPreviewMs + deltaMs;
    if (t < 0) t = 0;
    if (dur > 0 && t > dur) t = dur;
    setState(() => _scrubPreviewMs = t);
    _restartHideTimer();
  }

  // Confirm: now actually seek to the marker (one load), stay paused, and focus
  // play/pause so the user presses play to resume.
  void _commitScrub() {
    _controller?.seekTo(Duration(milliseconds: _scrubPreviewMs));
    setState(() => _scrubbing = false);
    _playPauseFocus.requestFocus();
    _restartHideTimer();
  }

  // Cancel (Back): discard the marker; nothing was seeked, so just restore
  // playback where it was.
  void _cancelScrub() {
    if (_wasPlayingBeforeScrub) _controller?.play();
    setState(() => _scrubbing = false);
    _playPauseFocus.requestFocus();
    _restartHideTimer();
  }

  // Touch / mouse drag on the seek bar: preview while dragging, seek once on
  // release, then resume if it was playing.
  void _touchScrubStart() {
    _wasPlayingBeforeScrub = _playing;
    _controller?.pause();
    setState(() => _scrubbing = true);
    _restartHideTimer();
  }

  void _touchScrubTo(Duration p) {
    setState(() => _scrubPreviewMs = p.inMilliseconds);
    _restartHideTimer();
  }

  void _touchScrubEnd() {
    _controller?.seekTo(Duration(milliseconds: _scrubPreviewMs));
    if (_wasPlayingBeforeScrub) _controller?.play();
    setState(() => _scrubbing = false);
    _restartHideTimer();
  }

  void _revealControls({bool focusPlay = false}) {
    final wasHidden = !_showControls;
    setState(() => _showControls = true);
    _restartHideTimer();
    if (focusPlay || wasHidden) {
      // Auto-focus the play/pause control whenever the controls appear so a
      // D-pad/remote user always lands somewhere visible.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _playPauseFocus.canRequestFocus) {
          _playPauseFocus.requestFocus();
        }
      });
    }
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), _maybeHide);
  }

  void _maybeHide() {
    if (!mounted || _scrubbing) return;
    if (_playing) {
      _hideControls();
    } else {
      // Paused/buffering — re-check shortly so the controls still fade once
      // playback is actually running, instead of giving up.
      _hideTimer = Timer(const Duration(seconds: 2), _maybeHide);
    }
  }

  // Hide the controls and move focus back to the root scope so the next remote
  // key is caught (to reveal them) instead of vanishing into a hidden control.
  void _hideControls() {
    setState(() => _showControls = false);
    _rootScope.requestFocus();
  }

  // ---- Lifecycle ---------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The player runs with handleLifecycle:false (we manage it ourselves), so
    // nothing pauses the native ExoPlayer on background. Pause it explicitly the
    // moment the app leaves the foreground, otherwise audio keeps playing behind
    // whatever's on top. _backgrounded also stops the tick from auto-resuming.
    if (state == AppLifecycleState.resumed) {
      _backgrounded = false;
      return;
    }
    _backgrounded = true;
    _controller?.pause();
    // While leaving, don't re-arm ActivePlayback (a transient inactive during
    // the exit dialog/pop would otherwise trigger auto-resume → a 2nd player).
    if (_leaving) return;
    _saveProgress();
    if (_mode == PlayerMode.stream) {
      ActivePlayback.save(
        tmdbId: _tmdbId,
        type: _type,
        season: _season,
        episode: _episode,
      );
    }
  }

  Future<bool> _confirmExit() async {
    _controller?.pause();
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.charcoalLight,
        title: const Text('Stop watching?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('Do you want to leave the video?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          _DialogButton(
            label: 'Keep watching',
            autofocus: true,
            onTap: () => Navigator.pop(ctx, false),
          ),
          _DialogButton(
            label: 'Leave',
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (leave == true) {
      // Mark leaving first so no lifecycle event re-saves ActivePlayback, stop
      // audio immediately, persist progress, and clear the resume pointer.
      _leaving = true;
      PlayerRuntime.leftAt = _now;
      _controller?.pause();
      _saveProgress();
      ActivePlayback.clear();
      return true;
    }
    _controller?.play();
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    PlayerRuntime.isOpen = false;
    _tick?.cancel();
    _hideTimer?.cancel();
    _loadTimer?.cancel();
    _bufferDebounce?.cancel();
    _saveProgress();
    // Detach our listener before teardown so the controller's final events
    // don't call back into this (now-defunct) State.
    _controller?.removeEventsListener(_onEvent);
    _controller?.pause(); // stop audio immediately, before teardown
    // forceDispose is REQUIRED: the config sets autoDispose:false, so a plain
    // dispose() early-returns without releasing the native ExoPlayer — it would
    // keep playing audio in the background and leak ~80 MB. forceDispose tears
    // the player down for real.
    _controller?.dispose(forceDispose: true);
    _rootScope.dispose();
    _playPauseFocus.dispose();
    _seekFocus.dispose();
    _skipFocus.dispose();
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ---- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_scrubbing) {
          _cancelScrub(); // Back during scrubbing cancels, doesn't exit
          return;
        }
        final leave = await _confirmExit();
        if (!context.mounted) return;
        if (leave) context.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: FocusScope(
          node: _rootScope,
          // NOTE: no autofocus — while controls are visible the play/pause
          // button must own focus so D-pad arrows can move between controls.
          // This handler fires for every key while the player has focus, incl.
          // when focus has fallen back to this scope.
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            // During the error screen (or while loading), don't intercept — let
            // the Retry / Open-in-YouTube button receive D-pad focus + OK.
            if (_errorMsg != null || _loading) return KeyEventResult.ignored;
            if (!_showControls) {
              // If a Skip Recap / Skip Intro / Next Episode button is showing,
              // it's focused — let the OK/Select key activate IT instead of
              // just revealing the controls.
              if (_actionKind != null && _isActivateKey(event.logicalKey)) {
                return KeyEventResult.ignored;
              }
              // Otherwise any remote key just reveals the controls and lands
              // focus on play/pause — it does not activate anything.
              _revealControls();
              return KeyEventResult.handled;
            }
            _restartHideTimer();
            // Recover if focus was lost (e.g. a focused control got rebuilt
            // away) so navigation keeps working no matter how much the user
            // moves around the controls.
            final pf = FocusManager.instance.primaryFocus;
            if (pf == null || pf == _rootScope) {
              _playPauseFocus.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored; // let the focused control handle it
          },
          child: GestureDetector(
            onTap: () {
              if (_showControls) {
                _hideControls();
              } else {
                _revealControls();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_controller != null)
                  BetterPlayer(controller: _controller!),
                _subtitleOverlay(),
                // While loading OR rebuffering, show ONLY the banner screen
                // (episode/series art fading to black + spinner) — no controls.
                if (_loading || _buffering)
                  Positioned.fill(child: _loadingOverlay()),
                if (_errorMsg != null) _errorView(),
                if (_errorMsg == null && _showControls && !_loading && !_buffering)
                  _controlsOverlay(),
                if (_errorMsg == null && !_loading && !_buffering)
                  _segmentActionOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Loading screen: the content backdrop, radially masked so it stays bright
  /// toward the top-right and fades smoothly into black on all sides (round, no
  /// straight/cut edges), with a % ring over a soft radial shadow.
  Widget _loadingOverlay() {
    // Episode still (rendered at backdrop size) if we have one, else the series
    // backdrop.
    final url = backdropUrl(_episodeStillPath ?? _backdropPath);
    final pct = _loadProgress.round();
    // Mid-playback rebuffer → indeterminate spinner + "Buffering"; initial load
    // → determinate % ring.
    final isBuffering = _buffering && !_loading;
    return LayoutBuilder(
      builder: (context, c) => Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (url != null)
            Positioned.fill(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const RadialGradient(
                  center: Alignment(0.55, -0.35), // bright toward top-right
                  radius: 1.05,
                  colors: [Colors.white, Colors.white, Color(0x00FFFFFF)],
                  stops: [0.0, 0.4, 0.95],
                ).createShader(rect),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  alignment: Alignment.topRight,
                  memCacheWidth:
                      (c.maxWidth * MediaQuery.devicePixelRatioOf(context))
                          .round()
                          .clamp(320, 1280),
                ),
              ),
            ),
          Center(
            child: Container(
              width: 150,
              height: 150,
              alignment: Alignment.center,
              // Soft radial shadow (fades out — no hard disc edge).
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0xA6000000), Color(0x00000000)],
                  stops: [0.3, 1.0],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: CircularProgressIndicator(
                      // Indeterminate while rebuffering (no meaningful %).
                      value: isBuffering
                          ? null
                          : (_loadProgress / 100).clamp(0.0, 1.0),
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                      strokeWidth: 4,
                    ),
                  ),
                  Text(
                    isBuffering ? 'Buffering' : '$pct%',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isBuffering ? 13 : 20,
                      fontWeight: FontWeight.w700,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subtitleOverlay() {
    final text = _subtitleText;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    // Size the subtitle as a fraction of screen width, not a fixed pixel size.
    // A TV renders at a higher density (smaller logical width) than the test
    // box, so a fixed 50px looked correct on the emulator but was giant on the
    // TV. 0.026 * 1920 = 50 (unchanged on the 1920-logical emulator).
    final width = MediaQuery.of(context).size.width;
    // A touch smaller than before on the TV's logical width.
    final fontSize = (width * 0.032).clamp(20.0, 44.0);
    final baseStyle = TextStyle(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      height: 1.2,
      // Layered soft shadow (a wider halo, not a darker box) so the text stays
      // readable even over on-screen text / bright scenes.
      shadows: const [
        Shadow(offset: Offset(0, 1), blurRadius: 6, color: Color(0xCC000000)),
        Shadow(offset: Offset(0, 0), blurRadius: 14, color: Color(0x99000000)),
      ],
    );
    return Positioned(
      left: 24,
      right: 24,
      bottom: _showControls ? 135 : 55,
      child: IgnorePointer(
        child: Text.rich(
          _subtitleSpan(text, baseStyle),
          textAlign: TextAlign.center,
          style: baseStyle,
        ),
      ),
    );
  }

  /// Parses subtitle markup: renders <i>/<b> as italic/bold, strips other tags,
  /// and decodes common HTML entities.
  TextSpan _subtitleSpan(String raw, TextStyle base) {
    final children = <TextSpan>[];
    var italic = false;
    var bold = false;
    final re = RegExp(r'(<[^>]+>)|([^<]+)');
    for (final m in re.allMatches(raw)) {
      final tag = m.group(1);
      final txt = m.group(2);
      if (tag != null) {
        final t = tag.toLowerCase().replaceAll(' ', '');
        if (t == '<i>') {
          italic = true;
        } else if (t == '</i>') {
          italic = false;
        } else if (t == '<b>') {
          bold = true;
        } else if (t == '</b>') {
          bold = false;
        }
        // other tags (e.g. <font>, <u>) are stripped
      } else if (txt != null) {
        children.add(TextSpan(
          text: _decodeEntities(txt),
          style: TextStyle(
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            fontWeight: bold ? FontWeight.w800 : base.fontWeight,
          ),
        ));
      }
    }
    return TextSpan(children: children);
  }

  String _decodeEntities(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");

  Widget _errorView() {
    final isTrailer = _mode == PlayerMode.trailer;
    final openYt = isTrailer && _trailerKey != null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_errorMsg!,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Focusable + autofocused so the D-pad can activate it.
              _DialogButton(
                label: openYt ? 'Open in YouTube' : 'Retry',
                autofocus: true,
                onTap: () {
                  if (openYt) {
                    launchUrl(Uri.parse(youTubeUrl(_trailerKey!)),
                        mode: LaunchMode.externalApplication);
                  } else {
                    _retryCount = 0;
                    _resolveAndPlay();
                  }
                },
              ),
              const SizedBox(width: 12),
              _DialogButton(
                label: 'Back',
                onTap: () {
                  _leaving = true;
                  PlayerRuntime.leftAt = _now;
                  ActivePlayback.clear();
                  if (mounted) context.pop();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _titleText() {
    if (_mode == PlayerMode.trailer) return const SizedBox.shrink();
    final title = _mediaTitle ?? '';
    String label = title;
    if (_isTv && _season != null && _episode != null) {
      final s = _season!.toString().padLeft(2, '0');
      final e = _episode!.toString().padLeft(2, '0');
      label = '$title   S${s}E$e';
      if (_episodeName != null && _episodeName!.isNotEmpty) {
        label = '$label: $_episodeName';
      }
    }
    if (label.isEmpty) return const SizedBox.shrink();
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _controlsOverlay() {
    final isStream = _mode == PlayerMode.stream;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.8),
          ],
          stops: const [0, 0.5, 1],
        ),
      ),
      child: Column(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _FocusIconButton(
                    icon: Icons.arrow_back,
                    onTap: () async {
                      final leave = await _confirmExit();
                      if (!mounted) return;
                      if (leave) context.pop();
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _titleText()),
                ],
              ),
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isStream && _prevRef != null) ...[
                _FocusIconButton(
                  key: const ValueKey('prev'),
                  icon: Icons.skip_previous,
                  onTap: () => _playEpisode(_prevRef!),
                ),
                const SizedBox(width: 14),
              ],
              _FocusIconButton(
                key: const ValueKey('replay15'),
                icon: Icons.replay,
                label: '15',
                spinOnTap: -1.0, // rewind: spin left, back to place
                onTap: () => _seekBy(-_seekStepMs),
              ),
              const SizedBox(width: 14),
              _FocusIconButton(
                key: const ValueKey('playpause'),
                icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 64,
                focusNode: _playPauseFocus,
                autofocus: true, // land focus here whenever controls appear
                onTap: _togglePlay,
              ),
              const SizedBox(width: 14),
              _FocusIconButton(
                key: const ValueKey('forward15'),
                icon: Icons.replay,
                label: '15',
                flipHorizontally: true, // mirror → clockwise "forward" arrow
                spinOnTap: 1.0, // forward: spin right, back to place
                onTap: () => _seekBy(_seekStepMs),
              ),
              if (isStream && _nextRef != null) ...[
                const SizedBox(width: 14),
                _FocusIconButton(
                  key: const ValueKey('next'),
                  icon: Icons.skip_next,
                  onTap: () => _playEpisode(_nextRef!),
                ),
              ],
            ],
          ),
          const Spacer(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Builder(builder: (context) {
                final displayPos = _scrubbing
                    ? Duration(milliseconds: _scrubPreviewMs)
                    : _position;
                return Row(
                children: [
                  Text(
                    _fmt(displayPos),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SeekBar(
                      position: displayPos,
                      duration: _duration,
                      buffered: _bufferedFraction,
                      focusNode: _seekFocus,
                      scrubbing: _scrubbing,
                      onEnterScrub: _enterScrub,
                      onCommitScrub: _commitScrub,
                      onCancelScrub: _cancelScrub,
                      onSeekStep: _scrubStep,
                      onTouchScrubStart: _touchScrubStart,
                      onTouchScrubTo: _touchScrubTo,
                      onTouchScrubEnd: _touchScrubEnd,
                      onSeekTo: (p) {
                        _controller?.seekTo(p);
                        _controller?.play();
                        _restartHideTimer();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(_fmt(_duration),
                      style: const TextStyle(color: Colors.white)),
                  if (isStream) ...[
                    _FocusIconButton(
                      icon: Icons.closed_caption,
                      onTap: _showSubtitleDialog,
                    ),
                    const SizedBox(width: 6),
                    _FocusIconButton(
                      icon: Icons.upload_file,
                      onTap: _uploadSubtitle,
                    ),
                    const SizedBox(width: 6),
                    _FocusIconButton(
                      icon: Icons.settings,
                      onTap: _showQualityDialog,
                    ),
                  ],
                ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // Contextual Skip Recap / Skip Intro / Next Episode button, driven by
  // introdb segment timings. Auto-focuses when it appears so the remote's OK
  // button triggers it immediately (the expected TV behaviour); positioned
  // above the control bar so it doesn't collide with the transport row.
  Widget _segmentActionOverlay() {
    final kind = _actionKind;
    if (kind == null) return const SizedBox.shrink();
    late final String label;
    late final IconData icon;
    late final VoidCallback onTap;
    switch (kind) {
      case 'intro':
        label = 'Skip Intro';
        icon = Icons.fast_forward;
        onTap = () => _seekToMs(_segments!.intro!.endMs);
        break;
      case 'recap':
        label = 'Skip Recap';
        icon = Icons.fast_forward;
        onTap = () => _seekToMs(_segments!.recap!.endMs);
        break;
      case 'next':
      default:
        label = 'Next Episode';
        icon = Icons.skip_next;
        onTap = () {
          if (_nextRef != null) _playEpisode(_nextRef!);
        };
        break;
    }
    return Positioned(
      right: 28,
      bottom: _showControls ? 150 : 60,
      child: _SkipButton(
        // A key per kind so the button remounts (and re-autofocuses) when the
        // active segment changes.
        key: ValueKey(kind),
        focusNode: _skipFocus,
        label: label,
        icon: icon,
        onTap: onTap,
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

/// Prominent Skip Recap / Skip Intro / Next Episode button. Always shows a
/// white border (legible over video); inverts to a solid white fill on focus.
/// Auto-focuses on appear so the remote OK button triggers it right away.
class _SkipButton extends StatefulWidget {
  const _SkipButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.focusNode,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  State<_SkipButton> createState() => _SkipButtonState();
}

class _SkipButtonState extends State<_SkipButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: true,
      onFocusChange: (f) => setState(() => _focused = f),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: _focused ? AppColors.focusRing : Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.focusRing, width: 2),
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

/// Icon button with a clear focus ring for D-pad navigation.
class _FocusIconButton extends StatefulWidget {
  const _FocusIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 40,
    this.focusNode,
    this.autofocus = false,
    this.spinOnTap = 0.0,
    this.label,
    this.flipHorizontally = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Full turns to spin the icon on tap (e.g. +1 = one clockwise spin for +15s,
  /// -1 = counter-clockwise for -15s). 0 = no spin.
  final double spinOnTap;

  /// Small number drawn in the middle of the icon (e.g. "15" for the ±15s skip
  /// buttons — Material has no replay_15/forward_15 glyph, so we overlay it on a
  /// plain circular arrow).
  final String? label;

  /// Mirror the icon horizontally — turns the counter-clockwise `Icons.replay`
  /// arrow into a clockwise "forward" arrow for the +15s button.
  final bool flipHorizontally;

  @override
  State<_FocusIconButton> createState() => _FocusIconButtonState();
}

class _FocusIconButtonState extends State<_FocusIconButton>
    with TickerProviderStateMixin {
  bool _focused = false;

  // A quick "blink"/pulse played on every activation (D-pad OK or tap): the
  // icon dips to 0.82 and springs back, giving tactile feedback on -30/+30 etc.
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _pulse = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.82), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.82, end: 1.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));

  // A smooth one-turn spin on tap (direction from spinOnTap); ends back at 0.
  late final AnimationController _spinCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late final Animation<double> _spin = Tween<double>(
    begin: 0,
    end: widget.spinOnTap,
  ).animate(CurvedAnimation(parent: _spinCtrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  void _handleActivate() {
    widget.onTap();
    _pulseCtrl.forward(from: 0);
    if (widget.spinOnTap != 0) _spinCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    const iconShadow = [Shadow(color: Color(0xB3000000), blurRadius: 10)];
    Widget arrow = Icon(
      widget.icon,
      color: Colors.white,
      size: widget.size * 0.7,
      // Soft shadow so the white icon stays legible over bright video.
      shadows: iconShadow,
    );
    if (widget.flipHorizontally) {
      arrow = Transform.flip(flipX: true, child: arrow);
    }
    Widget icon = widget.label == null
        ? arrow
        : Stack(
            alignment: Alignment.center,
            children: [
              arrow,
              // Number sits in the open centre of the circular arrow; kept out
              // of the flip so "15" is never mirrored.
              Text(
                widget.label!,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.size * 0.26,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                  shadows: iconShadow,
                ),
              ),
            ],
          );
    if (widget.spinOnTap != 0) {
      icon = RotationTransition(turns: _spin, child: icon);
    }
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _handleActivate();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleActivate,
        child: AnimatedScale(
          scale: _focused ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: ScaleTransition(
            scale: _pulse, // click blink, multiplies with the focus scale
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Transparent disc; a white ring marks focus (no filled bg).
                color: Colors.transparent,
                border: _focused
                    ? Border.all(color: Colors.white, width: 2.5)
                    : null,
              ),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }
}

/// A dialog action button (Keep watching / Leave) with a clear D-pad focus
/// state — inverts to a solid light fill when focused.
class _DialogButton extends StatefulWidget {
  const _DialogButton({
    required this.label,
    required this.onTap,
    this.autofocus = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: _focused ? AppColors.focusRing : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _focused ? AppColors.focusRing : AppColors.textSecondary,
              width: 1.5,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _focused ? Colors.black : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// A subtitle/quality dialog row with an unmistakable D-pad focus state — the
/// focused row inverts to a solid light fill so it's obvious on a TV.
class _DialogOption extends StatefulWidget {
  const _DialogOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_DialogOption> createState() => _DialogOptionState();
}

class _DialogOptionState extends State<_DialogOption> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final fg = _focused ? Colors.black : AppColors.textPrimary;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          color: _focused ? AppColors.focusRing : Colors.transparent,
          child: Row(
            children: [
              Icon(
                widget.selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: _focused
                    ? Colors.black
                    : (widget.selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary),
                size: 18,
              ),
              const SizedBox(width: 12),
              Text(widget.label, style: TextStyle(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// D-pad friendly seek bar. When focused, arrows move to adjacent controls;
/// pressing Select/Enter enters "scrub mode" where Left/Right seek by 30s and
/// Up/Down (or Select again) exits. Touch: tap anywhere on the bar to seek.
class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.focusNode,
    required this.scrubbing,
    required this.onEnterScrub,
    required this.onCommitScrub,
    required this.onCancelScrub,
    required this.onSeekStep,
    required this.onTouchScrubStart,
    required this.onTouchScrubTo,
    required this.onTouchScrubEnd,
    required this.onSeekTo,
  });

  final Duration position;
  final Duration duration;
  final double buffered; // buffered-ahead fraction (0..1)
  final FocusNode focusNode;
  final bool scrubbing;
  final VoidCallback onEnterScrub;
  final VoidCallback onCommitScrub;
  final VoidCallback onCancelScrub;
  final void Function(int deltaMs) onSeekStep;
  final VoidCallback onTouchScrubStart;
  final void Function(Duration pos) onTouchScrubTo;
  final VoidCallback onTouchScrubEnd;
  final void Function(Duration pos) onSeekTo;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  bool _focused = false;

  static final _selectKeys = {
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.gameButtonA,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Handle both the initial press and auto-repeats (holding to seek); ignore
    // key-up only.
    final isDown = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    if (!isDown && !isRepeat) return KeyEventResult.ignored;
    final k = event.logicalKey;

    if (widget.scrubbing) {
      // Left/Right seek on press AND while held; consumed so focus never moves.
      if (k == LogicalKeyboardKey.arrowLeft) {
        widget.onSeekStep(-15000);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        widget.onSeekStep(15000);
        return KeyEventResult.handled;
      }
      if (isDown) {
        if (_selectKeys.contains(k) ||
            k == LogicalKeyboardKey.arrowUp ||
            k == LogicalKeyboardKey.arrowDown) {
          widget.onCommitScrub();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.goBack ||
            k == LogicalKeyboardKey.escape) {
          widget.onCancelScrub();
          return KeyEventResult.handled;
        }
      }
      // Consume everything else (incl. repeats) so focus can't move mid-scrub.
      return KeyEventResult.handled;
    }

    // Not scrubbing: Select/Enter starts scrubbing; arrows move focus normally.
    if (isDown && _selectKeys.contains(k)) {
      widget.onEnterScrub();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Converts a local X offset on the bar into a media position in ms.
  int? _msForDx(double dx) {
    final durMs = widget.duration.inMilliseconds;
    if (durMs <= 0) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return null;
    final frac = (dx / box.size.width).clamp(0.0, 1.0);
    return (frac * durMs).round();
  }

  @override
  Widget build(BuildContext context) {
    final durMs = widget.duration.inMilliseconds;
    final frac =
        durMs > 0 ? (widget.position.inMilliseconds / durMs).clamp(0.0, 1.0) : 0.0;
    final active = _focused || widget.scrubbing;
    final barHeight = active ? 6.0 : 3.0;
    final accent = widget.scrubbing ? AppColors.ratingYellow : Colors.white;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      onFocusChange: (f) => setState(() => _focused = f),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Tap-to-seek (mouse/touch): one seek to the tapped point.
        onTapUp: (d) {
          final ms = _msForDx(d.localPosition.dx);
          if (ms == null) return;
          widget.focusNode.requestFocus();
          widget.onSeekTo(Duration(milliseconds: ms));
        },
        // Drag-to-seek (mouse/touch): smooth preview, seek once on release.
        onHorizontalDragStart: (d) {
          if (widget.duration.inMilliseconds <= 0) return;
          widget.focusNode.requestFocus();
          widget.onTouchScrubStart();
          final ms = _msForDx(d.localPosition.dx);
          if (ms != null) widget.onTouchScrubTo(Duration(milliseconds: ms));
        },
        onHorizontalDragUpdate: (d) {
          final ms = _msForDx(d.localPosition.dx);
          if (ms != null) widget.onTouchScrubTo(Duration(milliseconds: ms));
        },
        onHorizontalDragEnd: (_) => widget.onTouchScrubEnd(),
        child: SizedBox(
          height: 36,
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
                  // Buffered-ahead track (lighter than the played track).
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
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
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

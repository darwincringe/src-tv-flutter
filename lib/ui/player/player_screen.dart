import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme.dart';
import '../../data/models/details_dto.dart';
import '../../data/repository/media_repository.dart';
import '../../data/store/active_playback.dart';
import '../../data/store/subtitle_pref.dart';
import '../../data/store/watch_progress.dart';
import '../../data/tmdb/image_urls.dart';
import '../../data/youtube/youtube_extractor.dart';
import 'player_args.dart';
import 'subtitle_config.dart';

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
  static const int _seekStepMs = 30000;
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
  bool _isTv = false;
  List<Season> _seasons = [];
  _EpisodeRef? _nextRef;
  _EpisodeRef? _prevRef;

  // Streaming state
  final List<SubtitleOption> _uploadedSubs = [];
  List<SubtitleOption> _subOptions = []; // all current subtitle options
  int _resumeTargetMs = 0;
  bool _resumeDone = true;
  int _retryCount = 0;

  // UI state
  bool _loading = true;
  String? _errorMsg;
  bool _showControls = true;
  bool _playing = false;
  bool _showNextOverlay = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // TV / D-pad control state
  final FocusNode _playPauseFocus = FocusNode(debugLabel: 'playpause');
  final FocusNode _seekFocus = FocusNode(debugLabel: 'seek');
  bool _scrubbing = false; // seek-bar "scrub mode" active
  int _scrubPreviewMs = 0; // marker position while scrubbing (not yet applied)
  bool _wasPlayingBeforeScrub = false;
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

    _resolveAndPlay();
  }

  BetterPlayerController _buildController() {
    return BetterPlayerController(
      BetterPlayerConfiguration(
        fit: BoxFit.contain,
        autoPlay: true,
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
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        _retryCount = 0;
        // Don't seek here — seeking right after init stalls ExoPlayer. The
        // resume seek is applied from the tick once playback is advancing.
        _controller?.play();
        if (mounted) setState(() => _loading = false);
        _startTick();
        break;
      case BetterPlayerEventType.play:
        _playing = true;
        WakelockPlus.enable();
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
      case BetterPlayerEventType.exception:
        _retryOrError('Playback error');
        break;
      default:
        break;
    }
  }

  // ---- Resolve + play ----------------------------------------------------

  Future<void> _resolveAndPlay() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
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
          _isTv = d.isTv;
          _seasons = d.seasons;
        } catch (_) {}
      }
      if (_type == 'tv' && _episode != null) {
        try {
          final eps = await repo.episodes(_tmdbId, _season ?? 1);
          _episodeName =
              eps.firstWhere((e) => e.episodeNumber == _episode).name;
        } catch (_) {
          _episodeName = null;
        }
      }
      _computeEpisodeRefs();
      _resumeTargetMs = _savedResumePosition();
      _resumeDone = _resumeTargetMs <= 0;

      final subs = _buildSubtitleSources(res.subtitles);
      _controller ??= _buildController();
      await _controller!.setupDataSource(
        BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          res.hlsUrl!,
          videoFormat: BetterPlayerVideoFormat.hls,
          headers: const {'User-Agent': _userAgent},
          subtitles: subs,
          useAsmsSubtitles: false,
          useAsmsTracks: true,
          // Bound the buffer so each play uses far less heap; the default
          // (~50s) piled up across movies and OOM-crashed WSA's small heap.
          bufferingConfiguration: const BetterPlayerBufferingConfiguration(
            minBufferMs: 15000,
            maxBufferMs: 30000,
            bufferForPlaybackMs: 2500,
            bufferForPlaybackAfterRebufferMs: 5000,
          ),
        ),
      );
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

  List<BetterPlayerSubtitlesSource> _buildSubtitleSources(
    List<String> apiUrls,
  ) {
    final opts = [
      ...apiSubtitleOptions(apiUrls),
      ..._uploadedSubs,
    ];
    _subOptions = opts;
    final defaultIndex = _defaultSubtitleIndex(opts);

    return [
      for (var i = 0; i < opts.length; i++)
        BetterPlayerSubtitlesSource(
          type: opts[i].uri.startsWith('http')
              ? BetterPlayerSubtitlesSourceType.network
              : BetterPlayerSubtitlesSourceType.file,
          name: opts[i].label,
          urls: [opts[i].uri],
          selectedByDefault: i == defaultIndex,
        ),
    ];
  }

  /// Chooses the default subtitle: the remembered choice (matched by name, then
  /// language), else English (case-insensitive), else the first track. Returns
  /// -1 if the user previously turned subtitles off.
  int _defaultSubtitleIndex(List<SubtitleOption> opts) {
    final pref = SubtitlePrefStore.get(_type, _tmdbId, _season);
    if (pref?.off ?? false) return -1;
    if (pref != null) {
      if (pref.name != null) {
        final i = opts.indexWhere(
            (o) => o.label.toLowerCase() == pref.name!.toLowerCase());
        if (i >= 0) return i;
      }
      if (pref.language != null) {
        final i = opts.indexWhere((o) => (o.language ?? '') == pref.language);
        if (i >= 0) return i;
      }
    }
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

  void _rememberSubtitle(String? name) {
    final opt = _subOptions.firstWhere(
      (o) => o.label == name,
      orElse: () => SubtitleOption(uri: '', label: name ?? ''),
    );
    SubtitlePrefStore.save(
      _type,
      _tmdbId,
      _season,
      SubtitlePref(name: name, language: opt.language),
    );
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
    final source = BetterPlayerSubtitlesSource(
      type: BetterPlayerSubtitlesSourceType.file,
      name: opt.label,
      urls: [opt.uri],
    );
    _controller?.betterPlayerSubtitlesSourceList.add(source);
    _controller?.setupSubtitleSource(source);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subtitle added')),
      );
    }
  }

  void _showSubtitleDialog() {
    final list = _controller?.betterPlayerSubtitlesSourceList ?? [];
    final selectable = list
        .where((s) => s.type != BetterPlayerSubtitlesSourceType.none)
        .toList();
    if (selectable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No subtitles available')),
      );
      return;
    }
    final current = _controller?.betterPlayerSubtitlesSource;
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.charcoalLight,
        title: const Text('Subtitles',
            style: TextStyle(color: AppColors.textPrimary)),
        children: [
          _dialogOption(
            ctx,
            'Off',
            current == null ||
                current.type == BetterPlayerSubtitlesSourceType.none,
            () {
              final none = list.firstWhere(
                (s) => s.type == BetterPlayerSubtitlesSourceType.none,
                orElse: () => BetterPlayerSubtitlesSource(
                    type: BetterPlayerSubtitlesSourceType.none),
              );
              _controller?.setupSubtitleSource(none);
              SubtitlePrefStore.save(
                  _type, _tmdbId, _season, const SubtitlePref(off: true));
            },
          ),
          for (final s in selectable)
            _dialogOption(ctx, s.name ?? 'Subtitle', current == s, () {
              _controller?.setupSubtitleSource(s);
              _rememberSubtitle(s.name);
            }),
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
    return SimpleDialogOption(
      onPressed: () {
        onTap();
        Navigator.pop(ctx);
      },
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppColors.textPrimary)),
        ],
      ),
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
    setState(() {
      _season = ref.season;
      _episode = ref.episode;
      _episodeName = null;
      _showNextOverlay = false;
      _retryCount = 0;
    });
    _resolveAndPlay();
  }

  // ---- Progress ----------------------------------------------------------

  void _startTick() {
    _tick?.cancel();
    _ticks = 0;
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final v = _controller?.videoPlayerController?.value;
      if (v == null || !v.initialized) return;
      _position = v.position;
      _duration = v.duration ?? Duration.zero;
      // Apply the resume seek only once playback is genuinely advancing;
      // seeking earlier (on init) stalls ExoPlayer. This is the same path as a
      // manual seek, which works reliably.
      if (!_resumeDone &&
          _resumeTargetMs > 0 &&
          _position.inMilliseconds >= 800) {
        final target = _resumeTargetMs;
        _resumeTargetMs = 0;
        _resumeDone = true;
        _controller?.seekTo(Duration(milliseconds: target));
        _controller?.play();
      }
      _updateNextOverlay();
      final sub = _currentSubtitleText();
      final subChanged = sub != _subtitleText;
      if (subChanged) _subtitleText = sub;
      _ticks++;
      if (_ticks % 60 == 0) _saveProgress(); // every 30s
      if (mounted && (_showControls || subChanged)) {
        setState(() {});
      }
    });
  }

  /// Current subtitle text for the active source, computed from the parsed
  /// lines + position (we render it ourselves for a bold/shadow Netflix look).
  String? _currentSubtitleText() {
    final lines = _controller?.subtitlesLines ?? [];
    if (lines.isEmpty) return null;
    final pos = _position;
    for (final l in lines) {
      final start = l.start, end = l.end;
      if (start != null && end != null && pos >= start && pos <= end) {
        final t = (l.texts ?? []).join('\n').trim();
        return t.isEmpty ? null : t;
      }
    }
    return null;
  }

  void _updateNextOverlay() {
    if (_mode != PlayerMode.stream) return;
    final dur = _duration.inMilliseconds;
    final show =
        dur > 0 && _position.inMilliseconds >= dur * 0.95 && _nextRef != null;
    if (show != _showNextOverlay && mounted) {
      setState(() => _showNextOverlay = show);
    }
  }

  void _saveProgress() {
    if (_mode != PlayerMode.stream) return;
    if (!_resumeDone) return;
    final pos = _position.inMilliseconds;
    final dur = _duration.inMilliseconds;
    if (dur <= 0) return;
    if (pos >= dur * 0.95) {
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
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _playing && !_scrubbing) {
        setState(() => _showControls = false);
      }
    });
  }

  // ---- Lifecycle ---------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep watching'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true) {
      _saveProgress();
      ActivePlayback.clear();
      return true;
    }
    _controller?.play();
    return false;
  }

  @override
  void dispose() {
    PlayerRuntime.isOpen = false;
    _tick?.cancel();
    _hideTimer?.cancel();
    _saveProgress();
    _controller?.dispose();
    _playPauseFocus.dispose();
    _seekFocus.dispose();
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
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (!_showControls) {
              // First press just reveals the controls and focuses play/pause —
              // it does not activate anything.
              _revealControls();
              return KeyEventResult.handled;
            }
            _restartHideTimer();
            return KeyEventResult.ignored; // let the focused control handle it
          },
          child: GestureDetector(
            onTap: () {
              if (_showControls) {
                setState(() => _showControls = false);
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
                if (_loading)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                if (_errorMsg != null) _errorView(),
                if (_errorMsg == null && _showControls) _controlsOverlay(),
                if (_errorMsg == null && _showNextOverlay && _nextRef != null)
                  _nextEpisodeOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _subtitleOverlay() {
    final text = _subtitleText;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    const baseStyle = TextStyle(
      color: Colors.white,
      fontSize: 46,
      fontWeight: FontWeight.w700,
      height: 1.25,
      shadows: [
        Shadow(offset: Offset(0, 2), blurRadius: 7, color: Color(0xF2000000)),
        Shadow(blurRadius: 14, color: Color(0xB3000000)),
      ],
    );
    return Positioned(
      left: 24,
      right: 24,
      bottom: _showControls ? 150 : 56,
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_errorMsg!,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (isTrailer && _trailerKey != null) {
                launchUrl(Uri.parse(youTubeUrl(_trailerKey!)),
                    mode: LaunchMode.externalApplication);
              } else {
                _retryCount = 0;
                _resolveAndPlay();
              }
            },
            child: Text(
                isTrailer && _trailerKey != null ? 'Open in YouTube' : 'Retry'),
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
              if (isStream && _prevRef != null)
                _FocusIconButton(
                  icon: Icons.skip_previous,
                  onTap: () => _playEpisode(_prevRef!),
                ),
              _FocusIconButton(
                icon: Icons.replay_30,
                onTap: () => _seekBy(-_seekStepMs),
              ),
              _FocusIconButton(
                icon: _playing ? Icons.pause_circle : Icons.play_circle,
                size: 64,
                focusNode: _playPauseFocus,
                onTap: _togglePlay,
              ),
              _FocusIconButton(
                icon: Icons.forward_30,
                onTap: () => _seekBy(_seekStepMs),
              ),
              if (isStream && _nextRef != null)
                _FocusIconButton(
                  icon: Icons.skip_next,
                  onTap: () => _playEpisode(_nextRef!),
                ),
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
                      focusNode: _seekFocus,
                      scrubbing: _scrubbing,
                      onEnterScrub: _enterScrub,
                      onCommitScrub: _commitScrub,
                      onCancelScrub: _cancelScrub,
                      onSeekStep: _scrubStep,
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

  Widget _nextEpisodeOverlay() {
    return Positioned(
      right: 24,
      bottom: 110,
      child: FilledButton.icon(
        onPressed: () => _playEpisode(_nextRef!),
        icon: const Icon(Icons.skip_next),
        label: const Text('Next Episode'),
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

/// Icon button with a clear focus ring for D-pad navigation.
class _FocusIconButton extends StatefulWidget {
  const _FocusIconButton({
    required this.icon,
    required this.onTap,
    this.size = 40,
    this.focusNode,
  });
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final FocusNode? focusNode;

  @override
  State<_FocusIconButton> createState() => _FocusIconButtonState();
}

class _FocusIconButtonState extends State<_FocusIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
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
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _focused ? Colors.white24 : Colors.transparent,
            border: Border.all(
              color: _focused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Icon(widget.icon, color: Colors.white, size: widget.size * 0.7),
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
    required this.focusNode,
    required this.scrubbing,
    required this.onEnterScrub,
    required this.onCommitScrub,
    required this.onCancelScrub,
    required this.onSeekStep,
    required this.onSeekTo,
  });

  final Duration position;
  final Duration duration;
  final FocusNode focusNode;
  final bool scrubbing;
  final VoidCallback onEnterScrub;
  final VoidCallback onCommitScrub;
  final VoidCallback onCancelScrub;
  final void Function(int deltaMs) onSeekStep;
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
        widget.onSeekStep(-30000);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        widget.onSeekStep(30000);
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
        onTapDown: (d) {
          if (durMs <= 0) return;
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final frac = (d.localPosition.dx / box.size.width).clamp(0.0, 1.0);
          widget.focusNode.requestFocus();
          widget.onSeekTo(Duration(milliseconds: (frac * durMs).round()));
        },
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

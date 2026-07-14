import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_selector/file_selector.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme.dart';
import '../../data/models/details_dto.dart';
import '../../data/repository/media_repository.dart';
import '../../data/store/active_playback.dart';
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

  late final Player _player;
  late final VideoController _controller;
  final List<StreamSubscription> _subs = [];
  Timer? _saveTimer;
  Timer? _hideTimer;

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
  String? _hlsUrl;
  List<String> _apiSubs = [];
  final List<String> _uploadedSubs = [];
  String? _currentSubUri; // null == off
  int _retryCount = 0;

  // UI state
  bool _loading = true;
  String? _errorMsg;
  bool _showControls = true;
  bool _playing = false;
  bool _showNextOverlay = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    PlayerRuntime.isOpen = true;
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final a = widget.args;
    _mode = a.mode;
    _tmdbId = a.tmdbId ?? 0;
    _type = a.type ?? 'movie';
    _season = a.season;
    _episode = a.episode;
    _trailerKey = a.trailerKey;

    // Larger demuxer cache smooths HLS network hitches.
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024,
      ),
    );
    _controller = VideoController(_player);
    _wireStreams();
    _resolveAndPlay();
  }

  void _wireStreams() {
    _subs.add(_player.stream.position.listen((p) {
      _position = p;
      _updateNextOverlay();
      // Only repaint the overlay when it's visible; avoids rebuilding the whole
      // player tree several times a second during playback (reduces stutter).
      if (mounted && _showControls) setState(() {});
    }));
    _subs.add(_player.stream.duration.listen((d) {
      _duration = d;
      if (mounted) setState(() {});
    }));
    _subs.add(_player.stream.playing.listen((playing) {
      _playing = playing;
      if (playing) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
      if (mounted) setState(() {});
    }));
    _subs.add(_player.stream.completed.listen((done) {
      if (done) _onCompleted();
    }));
    _subs.add(_player.stream.error.listen((e) {
      _retryOrError('Playback error');
    }));
  }

  /// Waits until the media reports a real duration (loaded), so a resume seek
  /// lands correctly. Times out gracefully.
  Future<void> _waitForDuration() async {
    if (_player.state.duration.inMilliseconds > 0) return;
    try {
      await _player.stream.duration
          .firstWhere((d) => d.inMilliseconds > 0)
          .timeout(const Duration(seconds: 12));
    } catch (_) {}
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
      await _player.open(Media(sources.videoUrl), play: true);
      if (mounted) setState(() => _loading = false);
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
      _hlsUrl = res.hlsUrl;
      _apiSubs = res.subtitles;

      // Fetch title/seasons/poster once.
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
      final resumeMs = _savedResumePosition();

      // Open paused, seek to the resume point once the media is loaded, then
      // play. Seeking before playback starts avoids the "jumps to the right
      // spot then snaps back to 0" race.
      await _player.open(
        Media(_hlsUrl!, httpHeaders: {'User-Agent': _userAgent}),
        play: false,
      );
      if (resumeMs > 0) {
        await _waitForDuration();
        await _player.seek(Duration(milliseconds: resumeMs));
      }
      await _player.play();
      _applyDefaultSubtitle();
      _startSaveLoop();
      if (mounted) {
        setState(() {
          _loading = false;
          _retryCount = 0;
        });
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

  List<SubtitleOption> get _subtitleOptions => [
        ...apiSubtitleOptions(_apiSubs),
        for (var i = 0; i < _uploadedSubs.length; i++)
          uploadedSubtitleOption(_uploadedSubs[i], i),
      ];

  void _applyDefaultSubtitle() {
    final opts = _subtitleOptions;
    if (opts.isEmpty) return;
    // Prefer English (case-insensitive, match "en"/"eng"/"english" in the
    // detected language or the label); otherwise fall back to the first track.
    SubtitleOption? chosen;
    for (final o in opts) {
      final lang = (o.language ?? '').toLowerCase();
      final label = o.label.toLowerCase();
      if (lang == 'en' ||
          lang.contains('eng') ||
          label.contains('eng') ||
          label.contains('english')) {
        chosen = o;
        break;
      }
    }
    _selectSubtitle(chosen ?? opts.first);
  }

  void _selectSubtitle(SubtitleOption? opt) {
    if (opt == null) {
      _player.setSubtitleTrack(SubtitleTrack.no());
      setState(() => _currentSubUri = null);
      return;
    }
    _player.setSubtitleTrack(
      SubtitleTrack.uri(opt.uri, title: opt.label, language: opt.language),
    );
    setState(() => _currentSubUri = opt.uri);
  }

  Future<void> _uploadSubtitle() async {
    const group = XTypeGroup(
      label: 'subtitles',
      extensions: ['srt', 'vtt', 'ass', 'ssa'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    setState(() => _uploadedSubs.add(file.path));
    _selectSubtitle(uploadedSubtitleOption(file.path, _uploadedSubs.length - 1));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subtitle added')),
      );
    }
  }

  // ---- Quality -----------------------------------------------------------

  List<VideoTrack> get _qualityTracks {
    final seen = <int>{};
    final out = <VideoTrack>[];
    for (final t in _player.state.tracks.video) {
      final h = t.h;
      if (h == null || h <= 0) continue;
      if (seen.add(h)) out.add(t);
    }
    out.sort((a, b) => (b.h ?? 0).compareTo(a.h ?? 0));
    return out;
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

    // Next
    if (e < count) {
      _nextRef = _EpisodeRef(s, e + 1);
    } else {
      final laterSeasons = _seasons
          .where((x) => x.seasonNumber > s && (x.episodeCount ?? 0) > 0)
          .toList()
        ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      if (laterSeasons.isNotEmpty) {
        _nextRef = _EpisodeRef(laterSeasons.first.seasonNumber, 1);
      }
    }

    // Prev
    if (e > 1) {
      _prevRef = _EpisodeRef(s, e - 1);
    } else {
      final earlierSeasons = _seasons
          .where((x) => x.seasonNumber < s && (x.episodeCount ?? 0) > 0)
          .toList()
        ..sort((a, b) => b.seasonNumber.compareTo(a.seasonNumber));
      if (earlierSeasons.isNotEmpty) {
        final prev = earlierSeasons.first;
        _prevRef = _EpisodeRef(prev.seasonNumber, prev.episodeCount ?? 1);
      }
    }
  }

  void _playEpisode(_EpisodeRef ref) {
    _saveTimer?.cancel();
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

  void _startSaveLoop() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _saveProgress();
    });
  }

  void _updateNextOverlay() {
    if (_mode != PlayerMode.stream) return;
    final dur = _duration.inMilliseconds;
    final show = dur > 0 &&
        _position.inMilliseconds >= dur * 0.95 &&
        _nextRef != null;
    if (show != _showNextOverlay) {
      setState(() => _showNextOverlay = show);
    }
  }

  void _saveProgress() {
    if (_mode != PlayerMode.stream) return;
    final pos = _player.state.position.inMilliseconds;
    final dur = _player.state.duration.inMilliseconds;
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
      final dur = _player.state.duration.inMilliseconds;
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
    _player.seek(Duration(milliseconds: target));
  }

  void _revealControls() {
    setState(() => _showControls = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _showControls = false);
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
    _player.pause();
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
    _player.play();
    return false;
  }

  @override
  void dispose() {
    PlayerRuntime.isOpen = false;
    _saveTimer?.cancel();
    _hideTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmExit();
        if (!context.mounted) return;
        if (leave) context.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) _revealControls();
            return KeyEventResult.ignored;
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
                Video(
                  controller: _controller,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(
                    padding: EdgeInsets.fromLTRB(24, 24, 24, 48),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      backgroundColor: Color(0x00000000),
                      shadows: [
                        Shadow(blurRadius: 6, color: Color(0xE6000000)),
                        Shadow(
                          offset: Offset(1.5, 1.5),
                          blurRadius: 5,
                          color: Color(0xE6000000),
                        ),
                        Shadow(
                          offset: Offset(-1.5, -1.5),
                          blurRadius: 5,
                          color: Color(0xE6000000),
                        ),
                      ],
                    ),
                  ),
                ),
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
            child: Text(isTrailer && _trailerKey != null
                ? 'Open in YouTube'
                : 'Retry'),
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
    final dur = _duration.inMilliseconds.toDouble();
    final pos = _position.inMilliseconds.clamp(0, dur.toInt()).toDouble();
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
          // Top bar: back + title
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () async {
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
          // Center transport
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isStream && _prevRef != null)
                _ControlButton(
                  icon: Icons.skip_previous,
                  onTap: () => _playEpisode(_prevRef!),
                ),
              _ControlButton(
                icon: Icons.replay_30,
                onTap: () => _seekBy(-_seekStepMs),
              ),
              _ControlButton(
                icon: _playing ? Icons.pause_circle : Icons.play_circle,
                size: 64,
                autofocus: true,
                onTap: () => _player.playOrPause(),
              ),
              _ControlButton(
                icon: Icons.forward_30,
                onTap: () => _seekBy(_seekStepMs),
              ),
              if (isStream && _nextRef != null)
                _ControlButton(
                  icon: Icons.skip_next,
                  onTap: () => _playEpisode(_nextRef!),
                ),
            ],
          ),
          const Spacer(),
          // Bottom bar: position, slider, duration, subs, quality
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Text(_fmt(_position),
                      style: const TextStyle(color: Colors.white)),
                  Expanded(
                    child: Slider(
                      value: dur > 0 ? pos : 0,
                      max: dur > 0 ? dur : 1,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white24,
                      onChanged: (v) {
                        _revealControls();
                        _player.seek(Duration(milliseconds: v.toInt()));
                      },
                    ),
                  ),
                  Text(_fmt(_duration),
                      style: const TextStyle(color: Colors.white)),
                  if (isStream) ...[
                    IconButton(
                      icon: const Icon(Icons.closed_caption, color: Colors.white),
                      tooltip: 'Subtitles',
                      onPressed: _showSubtitleDialog,
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.upload_file, color: Colors.white),
                      tooltip: 'Upload Subtitle',
                      onPressed: _uploadSubtitle,
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.settings, color: Colors.white),
                      tooltip: 'Quality',
                      onPressed: _showQualityDialog,
                    ),
                  ],
                ],
              ),
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

  void _showSubtitleDialog() {
    final opts = _subtitleOptions;
    if (opts.isEmpty) {
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
          _dialogOption(ctx, 'Off', _currentSubUri == null,
              () => _selectSubtitle(null)),
          for (final o in opts)
            _dialogOption(ctx, o.label, _currentSubUri == o.uri,
                () => _selectSubtitle(o)),
        ],
      ),
    );
  }

  void _showQualityDialog() {
    final tracks = _qualityTracks;
    if (tracks.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only one quality available')),
      );
      return;
    }
    final currentId = _player.state.track.video.id;
    final isAuto = currentId == 'auto';
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.charcoalLight,
        title: const Text('Quality',
            style: TextStyle(color: AppColors.textPrimary)),
        children: [
          _dialogOption(ctx, 'Auto', isAuto,
              () => _player.setVideoTrack(VideoTrack.auto())),
          for (final t in tracks)
            _dialogOption(ctx, '${t.h}p', !isAuto && currentId == t.id,
                () => _player.setVideoTrack(t)),
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

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.autofocus = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: IconButton(
        autofocus: autofocus,
        iconSize: size,
        color: Colors.white,
        icon: Icon(icon),
        onPressed: onTap,
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../data/tmdb/image_urls.dart';
import 'player_args.dart';

/// Plays a YouTube trailer via the official IFrame embed (reliable — unlike the
/// deprecated muxed-stream extraction). YouTube's own controls are hidden; we
/// overlay our own D-pad-navigable transport (−10s / play-pause / +10s).
///
/// Key routing on a TV is the tricky part: the embedded WebView is a native
/// Android view that grabs hardware key events before Flutter's focus tree sees
/// them. So we (a) wrap the WebView in [IgnorePointer] so it can't take native
/// focus from a tap, and (b) intercept D-pad keys through a global
/// [HardwareKeyboard] handler and drive the transport ourselves, instead of
/// relying on per-widget focus key handling.
class YoutubeTrailerScreen extends StatefulWidget {
  const YoutubeTrailerScreen({super.key, required this.videoId});
  final String videoId;

  @override
  State<YoutubeTrailerScreen> createState() => _YoutubeTrailerScreenState();
}

class _YoutubeTrailerScreenState extends State<YoutubeTrailerScreen> {
  late final YoutubePlayerController _controller;

  // Transport buttons, left-to-right: replay-10, play/pause, forward-10.
  static const int _kReplay = 0;
  static const int _kPlay = 1;
  static const int _kForward = 2;
  final List<FocusNode> _nodes = [
    FocusNode(debugLabel: 'tReplay'),
    FocusNode(debugLabel: 'tPlay'),
    FocusNode(debugLabel: 'tForward'),
  ];
  int _idx = _kPlay;

  bool _showControls = true;
  bool _playing = false;
  bool _armedHide = false;
  bool _exiting = false;
  Duration _position = Duration.zero;
  Timer? _hideTimer;
  StreamSubscription<YoutubePlayerValue>? _stateSub;
  StreamSubscription<YoutubeVideoState>? _posSub;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: false,
        showFullscreenButton: false,
        enableCaption: false,
        strictRelatedVideos: true,
        playsInline: true,
      ),
    );
    _stateSub = _controller.stream.listen((value) {
      final playing = value.playerState == PlayerState.playing;
      if (playing && !_armedHide) {
        _armedHide = true;
        _restartHideTimer();
      }
      if (mounted && playing != _playing) setState(() => _playing = playing);
    });
    _posSub = _controller.videoStateStream.listen((s) => _position = s.position);
    HardwareKeyboard.instance.addHandler(_onKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes[_idx].requestFocus();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _hideTimer?.cancel();
    _stateSub?.cancel();
    _posSub?.cancel();
    _controller.close();
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  static final _navKeys = {
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    // Some hosts (e.g. WSA) surface the D-pad left/right as the Alt keys.
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
  };
  static final _leftKeys = {
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.altLeft,
  };
  static final _rightKeys = {
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.altRight,
  };
  static final _backKeys = {
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.browserBack,
  };
  static final _selectKeys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
  };

  /// Global D-pad handler. Returns true to consume the event.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final k = e.logicalKey;
    // Back/escape arrives here as a key event (not a system pop) when the
    // embedded WebView is present, so PopScope never fires — pop it ourselves.
    if (_backKeys.contains(k)) {
      _exit();
      return true;
    }
    final isNav = _navKeys.contains(k);
    final isSelect = _selectKeys.contains(k);
    if (!isNav && !isSelect) return false;

    if (!_showControls) {
      _reveal();
      return true;
    }
    _restartHideTimer();
    if (_leftKeys.contains(k)) {
      _move(-1);
    } else if (_rightKeys.contains(k)) {
      _move(1);
    } else if (isSelect) {
      _activate();
    }
    return true;
  }

  void _exit() {
    if (_exiting || !mounted) return;
    _exiting = true;
    // Guard the details screen underneath against a stray second back event
    // (WSA can deliver one back press as both a key event and a system pop).
    PlayerRuntime.backGuardUntil =
        DateTime.now().millisecondsSinceEpoch + 600;
    context.pop();
  }

  void _move(int delta) {
    final next = (_idx + delta).clamp(0, _nodes.length - 1);
    if (next == _idx) return;
    setState(() => _idx = next);
    _nodes[_idx].requestFocus();
  }

  void _activate() {
    switch (_idx) {
      case _kReplay:
        _seekBy(-10);
      case _kForward:
        _seekBy(10);
      default:
        _togglePlay();
    }
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _showControls = false);
    });
  }

  void _reveal() {
    setState(() => _showControls = true);
    _nodes[_idx].requestFocus();
    _restartHideTimer();
  }

  void _togglePlay() {
    if (_playing) {
      _controller.pauseVideo();
    } else {
      _controller.playVideo();
    }
    _restartHideTimer();
  }

  void _seekBy(int seconds) {
    final target = (_position.inSeconds + seconds).clamp(0, 1 << 30);
    _controller.seekTo(seconds: target.toDouble(), allowSeekAhead: true);
    _controller.playVideo();
    _restartHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back may arrive either as a system pop (here) or as a raw key event
      // (handled in _onKey); route both through the guarded _exit.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () => _showControls ? _restartHideTimer() : _reveal(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  // The WebView renders the video but must not receive pointer
                  // (and thus native focus) — our overlay drives playback.
                  child: IgnorePointer(
                    child: YoutubePlayer(
                      controller: _controller,
                      enableFullScreenOnVerticalDrag: false,
                    ),
                  ),
                ),
              ),
              if (_showControls) _controls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.7),
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
                  _TrailerButton(
                    icon: Icons.arrow_back,
                    onTap: _exit,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Trailer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  _TrailerButton(
                    icon: Icons.open_in_new,
                    onTap: () => launchUrl(
                      Uri.parse(youTubeUrl(widget.videoId)),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TrailerButton(
                icon: Icons.replay_10,
                focusNode: _nodes[_kReplay],
                onTap: () => _seekBy(-10),
              ),
              const SizedBox(width: 18),
              _TrailerButton(
                icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 64,
                focusNode: _nodes[_kPlay],
                onTap: _togglePlay,
              ),
              const SizedBox(width: 18),
              _TrailerButton(
                icon: Icons.forward_10,
                focusNode: _nodes[_kForward],
                onTap: () => _seekBy(10),
              ),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

/// White icon button with a focus ring — the trailer's D-pad transport control.
/// Focus is driven externally (via the parent's [HardwareKeyboard] handler);
/// this widget only reflects focus visually and supports tap for touch users.
class _TrailerButton extends StatefulWidget {
  const _TrailerButton({
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
  State<_TrailerButton> createState() => _TrailerButtonState();
}

class _TrailerButtonState extends State<_TrailerButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      canRequestFocus: widget.focusNode != null,
      onFocusChange: (f) => setState(() => _focused = f),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _focused ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _focused ? Colors.white.withValues(alpha: 0.12) : null,
              border: _focused
                  ? Border.all(color: Colors.white, width: 2.5)
                  : null,
            ),
            child: Icon(
              widget.icon,
              color: Colors.white,
              size: widget.size * 0.7,
              shadows: const [Shadow(color: Color(0xB3000000), blurRadius: 10)],
            ),
          ),
        ),
      ),
    );
  }
}

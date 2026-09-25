// Platform-selected player entry point.
//
// Native (Android/iOS) uses player_screen.dart (better_player_plus / ExoPlayer).
// The web build exports web_player_screen.dart (HTML5 <video> + hls.js) instead,
// keeping the Android-only better_player_plus plugin — and its dart:io deps —
// entirely out of the web compile. Both expose PlayerScreen({required args}).
export 'player_screen.dart' if (dart.library.html) 'web_player_screen.dart';

# SRC TV (Flutter)

A cross-platform **TV + phone** streaming front-end built with **Flutter**. It browses movies and
series from **TMDB**, resolves playable HLS streams from a self-hosted **extract backend**, and
plays them with **media_kit**. One codebase targets **Android TV** (D-pad), **Android phones**
(touch + portrait), and **iOS**, with **tvOS** planned.

This is a Flutter port of the original Kotlin/Jetpack Compose app (`../SRCTV`), aiming for full
feature parity.

> ⚠️ **Disclaimer** — SRC TV is a learning/personal project. It plays streams supplied by a
> third-party "extract" backend and pulls trailers via YouTube extraction. You are responsible for
> how you host and use those sources; only stream content you have the right to.

---

## Features

- **Browse** Home, Movies, and TV Series pages (hero banner + horizontal category rows).
- **Personalized rows** — *Continue Watching* and *Recommended for you* (from your watch history and
  searches; mixed on Home, movies-only on Movies, series-only on TV).
- **Search** with autocomplete suggestions (debounced).
- **Details** pages with cast & crew, "More like this", and (for series) season/episode pickers.
- **Player** (media_kit): HLS playback, quality picker, ±30s seek, subtitle selection + upload,
  default-English captions, resume/progress, prev/next-episode with cross-season rollover, auto-play
  next episode, keep-screen-awake while playing, and "return to what you were watching".
- **Watch trailers** in-app (extracted from YouTube via `youtube_explode_dart`).
- **Responsive** — side rail on TV/landscape, bottom nav in phone portrait.
- Local, on-device persistence for watch progress / search seeds (`shared_preferences`; structured
  to swap for a backend/DB later).

## How it works

```
                 ┌──────────────────────────┐
   Metadata ───► │  TMDB API                │  titles, art, cast, recommendations, search
                 │  api.themoviedb.org/3     │
                 └──────────────────────────┘
                 ┌──────────────────────────┐
   Streams  ───► │  Extract backend         │  GET /extract?tmdb_id=&type=movie|tv&season=&episode=
                 │  http://165.22.111.114... │  → { hls_url, subtitles[...] }
                 └──────────────────────────┘
                 ┌──────────────────────────┐
   Trailers ───► │  youtube_explode_dart    │  raw video/audio stream for the TMDB trailer key
                 └──────────────────────────┘
```

- **UI**: Flutter widgets (Material). D-pad focus is handled natively by Flutter's focus system;
  touch works on the same widgets, so no per-widget touch workaround is needed.
- **State**: **Riverpod** providers.
- **Data layer** (`lib/data/`): **dio** clients (TMDB key injected via an interceptor).
  `MediaRepository` is the single source of truth with in-memory caching (rows, details,
  recommendations, search). Models use `json_serializable` (run `build_runner` to generate).
- **Playback**: `media_kit` (libmpv-backed) `Player` + `Video` with an HLS source, external
  subtitle tracks, and D-pad-navigable custom controls.

## Tech stack

| Area | Choice |
|------|--------|
| Language / UI | Dart, Flutter (Material) |
| State mgmt | `flutter_riverpod` |
| Networking | `dio` (+ TMDB api_key interceptor) |
| Models / codegen | `json_serializable` + `json_annotation` + `build_runner` |
| Media | `media_kit`, `media_kit_video`, `media_kit_libs_video` (HLS) |
| Images | `cached_network_image` |
| Trailers | `youtube_explode_dart` |
| Navigation | `go_router` |
| Persistence | `shared_preferences` |
| Misc | `wakelock_plus` (keep-awake), `file_selector` (subtitle upload) |
| Metadata | TMDB API v3 |

## Requirements

- **Flutter SDK** (stable, 3.44+) and the bundled Dart SDK on your PATH. Run `flutter doctor`.
- **Android**: Android Studio + Android SDK (API 36), licenses accepted
  (`flutter doctor --android-licenses`). `minSdk` 21 (Android 5.0+ / Android TV 9+).
- **iOS**: macOS + Xcode (build on a Mac; not buildable on Windows).
- **Internet access** at runtime (TMDB, the extract backend, YouTube).
- The app uses **cleartext HTTP** for the extract backend (`usesCleartextTraffic` on Android, ATS
  exception on iOS).

## Getting started

```bash
# 1. Get packages
flutter pub get

# 2. Generate model code (json_serializable)
dart run build_runner build --delete-conflicting-outputs

# 3. Run on a connected device / emulator
flutter run

# 4. Build a sideload-installable APK
flutter build apk --debug     # or --release
# Output: build/app/outputs/flutter-apk/app-debug.apk
```

Install with `adb`:

```bash
adb devices
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

An **Android TV** emulator/device is recommended for the full D-pad experience; a phone works too
(touch + portrait). iOS/tvOS builds must be done on a Mac with Xcode.

## Configuration

These are currently constants in source (fine for local dev — move to `--dart-define` /
`String.fromEnvironment` before sharing publicly):

- **TMDB API key** — `lib/data/tmdb/tmdb_client.dart` (`apiKey`).
  Get a free key at <https://www.themoviedb.org/settings/api>.
- **Stream extract backend** — `lib/data/stream/stream_client.dart` (`baseUrl`). It must expose
  `GET /extract?tmdb_id={id}&type=movie|tv[&season=&episode=]` returning
  `{ success, hls_url, subtitles: [...] }`, plus the subtitle proxy endpoints.

## Project structure

```
lib/
├─ main.dart                    # ProviderScope + app root + lifecycle observer
├─ app.dart                     # MaterialApp.router, dark theme
├─ core/                        # theme, router, focus helpers
├─ data/
│  ├─ tmdb/                     # dio client, api, image URLs
│  ├─ stream/                   # extract client + response
│  ├─ models/                   # DTOs + domain models (+ generated *.g.dart)
│  ├─ repository/               # MediaRepository (cache, rows, recommended, continueWatching)
│  ├─ store/                    # watch_progress / recommendation_seeds / active_playback
│  └─ youtube/                  # trailer stream extractor
└─ ui/
   ├─ shell/                    # side rail / bottom nav
   ├─ browse/ home/ movies/ series/
   ├─ details/ search/ settings/
   ├─ player/                   # media_kit player + subtitle config + controls
   └─ widgets/                  # poster card, rows, hero, state views
```

## Notes & caveats

- Flutter's focus system gives D-pad + touch on the same widgets — no manual touch workaround.
- Trailer extraction depends on `youtube_explode_dart` and can break when YouTube changes; it's
  best-effort.
- The release APK is signed with the **debug** keystore so it installs for testing — replace with a
  real keystore before any public release.
- tvOS is planned but not yet configured; Flutter's tvOS support is experimental and `media_kit` on
  tvOS needs validation.

# Video Quality Plan — "blurry / not really 1080p" playback

## TL;DR

**This is not an encoder problem — it's a player track‑selection problem.**
The source already publishes a 1080p rendition. Our player (`better_player_plus`
→ ExoPlayer/media3) starts HLS at the **lowest** rendition and ramps up too
slowly/conservatively, so most of the time you're actually watching the 358p or
714p variant while assuming it's 1080p. Fixing the player's ABR (adaptive
bitrate) start behaviour gets crisp 1080p with graceful fallback. Re‑encoding on
the server would **not** help (you can't add detail a lossy source doesn't have)
and is only worth it for titles whose source truly lacks a 1080p ladder.

---

## Evidence

Dragonheart: Vengeance (`tmdb 666750`) master playlist actually offers three
renditions:

| Rendition | Resolution | Bandwidth | Codec (profile) |
|-----------|-----------|-----------|-----------------|
| Low       | 640×358   | 0.79 Mbps | avc1.42c01e (Baseline 3.0) |
| Mid       | 1280×714  | 3.26 Mbps | avc1.64001f (High 3.1) |
| **High**  | **1920×1072** | **5.54 Mbps** | avc1.640028 (High 4.0) |

So 1080p **is** available. The livepush.io comparison you ran looks crisp
because hls.js in a browser starts high (and that test stream is a single high
rendition), whereas our ExoPlayer setup starts low.

### Root cause in our code path

`better_player_plus 1.3.4` builds ExoPlayer like this
(`android/.../BetterPlayer.kt`):

```kotlin
private val trackSelector = DefaultTrackSelector(context)   // DEFAULT params
...
ExoPlayer.Builder(context)
    .setTrackSelector(trackSelector)   // no custom BandwidthMeter supplied
```

Consequences:
1. **No `setInitialBitrateEstimate`** → ExoPlayer's default initial bandwidth
   estimate (~1 Mbps region default) means the first segments are picked at the
   **0.79 Mbps / 358p** rendition. It only climbs after it has measured enough
   throughput — and short titles / seeks / modest measured bandwidth mean it
   frequently never reaches the 5.5 Mbps / 1080p rung.
2. **Default `DefaultTrackSelector` viewport constraint** caps video to the
   physical display size. Fine on a 1080p TV, but on smaller surfaces (or if the
   render surface is created smaller) it can cap resolution below 1080p.
3. The only quality knob `better_player_plus` exposes to Dart is
   `setTrackParameters(w, h, bitrate)` which sets a **maximum** (used for
   *capping*, not for forcing quality *up*).

Net: playback is biased toward the lowest rung → "blurry, I can see pixels."

---

## Options (ranked)

### Option A — Patch `better_player_plus` ABR start (recommended, low effort, keeps ExoPlayer)

Vendor the package (git fork or `dependency_overrides` + local path) and make a
~10‑line change in `BetterPlayer.kt`:

```kotlin
// Start high; only drop if bandwidth genuinely can't sustain it.
val bandwidthMeter = DefaultBandwidthMeter.Builder(context)
    .setInitialBitrateEstimate(12_000_000)   // ~12 Mbps → starts at top rung
    .build()

val trackSelector = DefaultTrackSelector(context).apply {
    setParameters(
        buildUponParameters()
            // don't cap to the render-surface size; allow the full 1080p rung
            .setViewportSize(Int.MAX_VALUE, Int.MAX_VALUE, false)
            // optional: hard-prefer the highest rung (disables downshift)
            // .setForceHighestSupportedBitrate(true)
    )
}

ExoPlayer.Builder(context)
    .setBandwidthMeter(bandwidthMeter)
    .setTrackSelector(trackSelector)
```

- **High initial estimate + no viewport cap** = starts at 1080p, and ExoPlayer's
  normal ABR still drops to 714p/358p if the network can't keep up → this is the
  "best quality, fall back if there's a problem" behaviour you asked for.
- Leave `setForceHighestSupportedBitrate` **off** so fallback still works; turn
  it on only if you want 1080p‑or‑buffer with no downshift.
- Pairs with a bumped buffer (we already tune `BetterPlayerBufferingConfiguration`).

**Risk:** maintaining a fork. Small, isolated change; easy to rebase.

### Option B — No‑fork interim: force the top track from Dart

After the data source initialises, read the ladder and pin the ceiling to the
top rung using the API `better_player_plus` already exposes:

```dart
// in player_screen after 'initialized'
final tracks = _controller!.betterPlayerAsmsTracks;      // available renditions
if (tracks.isNotEmpty) {
  final best = tracks.reduce((a, b) =>
      (a.height ?? 0) * (a.width ?? 0) >= (b.height ?? 0) * (b.width ?? 0) ? a : b);
  _controller!.setTrack(best);   // sets max = top rung; ABR may still pick lower
}
```

- Zero fork. Removes any viewport cap by explicitly allowing the top rung.
- **Limitation:** `setTrack` only raises the *ceiling* (it calls
  `setTrackParameters` = a max). It does **not** raise the initial bandwidth
  estimate, so ExoPlayer can still *start* low and ramp. Helps, but less
  decisively than Option A. Good as a first ship while the fork is prepared.

### Option C — Switch player to `media_kit` (libmpv)

`media_kit` wraps libmpv, which has excellent scaling/quality and exposes
`hls-bitrate=max` (and rich ABR control) directly. Best long‑term quality and
control, robust fallback.

- **Cost:** meaningful migration (replaces the whole playback layer, custom
  controls, subtitle overlay, resume logic). Revisit if Option A proves
  insufficient.

### Option D — Server-side re-encode (only if a title genuinely lacks 1080p)

For titles where the **source** ladder tops out at 720p, no player can invent
1080p detail. Only then consider transcoding on the extract backend with ffmpeg:

```
ffmpeg -i IN -c:v libx264 -preset vefast -crf 20 -maxrate 8M -bufsize 16M \
  -vf scale=-2:1080 -c:a aac -b:a 160k -hls_time 6 -hls_playlist_type vod out.m3u8
```

- **Caveats:** re-encoding a lossy source can only preserve, never improve,
  quality; it's CPU‑ and bandwidth‑heavy; and it adds latency to first play.
  Not worth it as a general fix. Reserve for specific low‑ladder titles.

---

## Recommended path

1. **Ship Option B now** (no fork) so the ceiling is never below 1080p.
2. **Add a quality readout** (log/show the currently selected `width×height`)
   to *prove* which rung is playing — confirms the diagnosis on the real TV.
3. **Do Option A** (fork + high initial estimate + no viewport cap) as the real
   fix; verify 1080p starts immediately and falls back cleanly on throttled
   network.
4. Only reach for **D** for individual titles whose source has no 1080p rung.

## Verify

- Real TV box only (WSA's emulated H.264 decoder crashes on the 1080p rung, so
  quality can't be judged there).
- Compare a title's on‑screen `width×height` before/after; play on a throttled
  connection to confirm graceful fallback.

## Sources

- ExoPlayer initial bitrate estimate / force highest bitrate discussion:
  https://github.com/google/ExoPlayer/issues/4508 ,
  https://github.com/google/ExoPlayer/issues/9808

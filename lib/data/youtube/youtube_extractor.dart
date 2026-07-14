import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Playable sources for a trailer. [audioUrl] is currently always null — we
/// return a muxed stream so a single URL feeds media_kit directly.
class PlaybackSources {
  final String videoUrl;
  final String? audioUrl;
  const PlaybackSources(this.videoUrl, [this.audioUrl]);
}

/// Extracts a playable trailer URL from a YouTube video id using
/// youtube_explode_dart. Mirrors the intent of the Kotlin NewPipe extractor:
/// prefer a muxed MP4 ≤720p, else the best available muxed stream.
class YouTubeExtractor {
  static Future<PlaybackSources?> streamsFor(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      final muxed = manifest.muxed.toList();
      if (muxed.isNotEmpty) {
        // Prefer mp4, then the highest resolution not exceeding 720p.
        final mp4 = muxed
            .where((s) => s.container.name.toLowerCase() == 'mp4')
            .toList();
        final pool = mp4.isNotEmpty ? mp4 : muxed;
        pool.sort(
          (a, b) =>
              b.videoResolution.height.compareTo(a.videoResolution.height),
        );
        final under = pool.where((s) => s.videoResolution.height <= 720);
        final chosen = under.isNotEmpty ? under.first : pool.first;
        return PlaybackSources(chosen.url.toString());
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      yt.close();
    }
  }
}

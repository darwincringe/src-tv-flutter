import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../ui/player/player_args.dart';

/// Navigation helpers. Details and the player are full-screen routes on the
/// root navigator.
///
/// On **web** we navigate with `go` so the address bar reflects the current
/// screen — shareable links that survive a refresh. (Imperative `push` does NOT
/// update the URL, and it leaves the browser URL out of sync with the page
/// stack, which lets a route-info re-sync tear the page down mid-request.)
/// On **native** we keep `push` so the Android/TV back stack is unchanged.
void _navTo(BuildContext context, String location, {Object? extra}) {
  if (kIsWeb) {
    context.go(location, extra: extra);
  } else {
    context.push(location, extra: extra);
  }
}

void openDetails(BuildContext context, String type, int id) {
  _navTo(context, '/details/$type/$id');
}

/// The shareable, refresh-safe player location for a title. TV episodes carry
/// the season/episode as query params; movies are just the id.
String watchLocation({
  required String type,
  required int tmdbId,
  int? season,
  int? episode,
}) {
  final base = '/watch/$type/$tmdbId';
  if (type == 'tv' && season != null && episode != null) {
    return '$base?s=$season&e=$episode';
  }
  return base;
}

void playStream(
  BuildContext context, {
  required int tmdbId,
  required String type,
  int? season,
  int? episode,
  String? backdropPath,
}) {
  _navTo(
    context,
    watchLocation(type: type, tmdbId: tmdbId, season: season, episode: episode),
    // `extra` carries only the backdrop for an instant loading image on in-app
    // navigation; on a fresh load (refresh/share) it's null and the player
    // fetches it from details.
    extra: PlayerArgs.stream(
      tmdbId: tmdbId,
      type: type,
      season: season,
      episode: episode,
      backdropPath: backdropPath,
    ),
  );
}

void playTrailer(BuildContext context, String trailerKey) {
  _navTo(context, '/trailer/$trailerKey');
}

/// Back for the full-screen routes. Native: pop the push stack (unchanged TV
/// behaviour). Web: we navigate with `go`, which leaves nothing to pop and has
/// unreliable browser-history semantics, so go to a deterministic parent
/// ([fallback], default Home) — e.g. the player returns to its details page.
void navBack(BuildContext context, {String fallback = '/home'}) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  context.go(fallback);
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../ui/player/player_args.dart';
import 'history_stub.dart' if (dart.library.html) 'history_web.dart';

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

/// One step back.
///
/// Web history is the source of truth: Back pops it, the same as the browser
/// button, so the player returns to details and details returns to Home,
/// Search, or whichever screen opened it. [go] is not used for that pop — it
/// would push another copy of the parent and the next Back would return here.
///
/// [fallback] is only for a page opened directly (nothing behind it). Native
/// still pops the push stack.
/// Browser-only. Native is a no-op; the navigator stack is the history there.
void installAppHistoryGuard({
  required Listenable listenable,
  required String Function() currentUri,
}) {
  installWebHistoryGuard(listenable: listenable, currentUri: currentUri);
}

void navBack(BuildContext context, {String fallback = '/home'}) {
  if (kIsWeb && platformCanHistoryBack()) {
    platformHistoryBack();
    return;
  }
  if (!kIsWeb && context.canPop()) {
    context.pop();
    return;
  }
  Router.neglect(context, () => context.go(fallback));
}

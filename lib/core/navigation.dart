import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../ui/player/player_args.dart';

/// Navigation helpers used by the screens. Details and the player are
/// full-screen routes on the root navigator.
void openDetails(BuildContext context, String type, int id) {
  context.push('/details/$type/$id');
}

void playStream(
  BuildContext context, {
  required int tmdbId,
  required String type,
  int? season,
  int? episode,
}) {
  context.push(
    '/player',
    extra: PlayerArgs.stream(
      tmdbId: tmdbId,
      type: type,
      season: season,
      episode: episode,
    ),
  );
}

void playTrailer(BuildContext context, String trailerKey) {
  context.push('/player', extra: PlayerArgs.trailer(trailerKey));
}

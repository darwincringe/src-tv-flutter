import 'package:flutter/material.dart';

import '../browse/media_browse_screen.dart';

class MoviesScreen extends StatelessWidget {
  const MoviesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MediaBrowseScreen(
      scope: 'movie',
      loadRows: (repo) => repo.movieRows(),
    );
  }
}

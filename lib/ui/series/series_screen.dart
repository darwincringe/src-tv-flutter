import 'package:flutter/material.dart';

import '../browse/media_browse_screen.dart';

class SeriesScreen extends StatelessWidget {
  const SeriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MediaBrowseScreen(
      scope: 'tv',
      loadRows: (repo) => repo.seriesRows(),
    );
  }
}

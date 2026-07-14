import 'package:flutter/material.dart';

import '../browse/media_browse_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MediaBrowseScreen(
      scope: 'home',
      showContinueWatching: true,
      loadRows: (repo) => repo.homeRows(),
    );
  }
}

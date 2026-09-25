import 'package:flutter/material.dart';

import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import '../../data/store/library_store.dart';
import '../../data/store/watch_progress.dart';
import '../widgets/poster_card.dart';

/// "My Library" — titles the user saved, most-recently-watched first. Local
/// only (no account needed); rebuilds when the library or watch progress
/// changes.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    LibraryStore.revision.addListener(_onChange);
    // Watching something re-sorts the library (last-watched order).
    WatchProgressStore.revision.addListener(_onChange);
  }

  @override
  void dispose() {
    LibraryStore.revision.removeListener(_onChange);
    WatchProgressStore.revision.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = LibraryStore.all();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 24, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My Library',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Recently watched first',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: items.isEmpty
                  ? _empty()
                  : GridView.builder(
                      // Don't clip the focused card's scale-up.
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.only(bottom: 24, right: 16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 132,
                        childAspectRatio: 2 / 3,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final it = items[i];
                        final mi = MediaItem(
                          id: it.tmdbId,
                          mediaType: it.type,
                          title: it.type == 'movie' ? it.title : null,
                          name: it.type == 'tv' ? it.title : null,
                          posterPath: it.posterPath,
                        );
                        return PosterCard(
                          item: mi,
                          autofocus: i == 0,
                          width: 132,
                          onTap: () => openDetails(context, it.type, it.tmdbId),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library_outlined,
                color: AppColors.textSecondary, size: 48),
            SizedBox(height: 12),
            Text(
              'Your library is empty',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
            ),
            SizedBox(height: 6),
            Text(
              'Add movies & series with the + button on their page.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

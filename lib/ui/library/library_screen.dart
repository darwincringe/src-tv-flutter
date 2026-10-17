import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import '../../data/repository/media_repository.dart';
import '../../data/store/library_store.dart';
import '../../data/store/watch_progress.dart';
import '../widgets/continue_watching_row.dart';
import '../widgets/poster_card.dart';

/// "My Library" — titles the user saved, most-recently-watched first. Local
/// only (no account needed); rebuilds when the library or watch progress
/// changes.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  List<WatchProgress> _continue = [];

  @override
  void initState() {
    super.initState();
    LibraryStore.revision.addListener(_onChange);
    WatchProgressStore.revision.addListener(_onChange);
  }

  bool _activated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_activated || !TickerMode.valuesOf(context).enabled) return;
    _activated = true;
    _loadContinue();
  }

  @override
  void dispose() {
    LibraryStore.revision.removeListener(_onChange);
    WatchProgressStore.revision.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted || !_activated) return;
    setState(() {});
    _loadContinue();
  }

  Future<void> _loadContinue() async {
    try {
      final list =
          await ref.read(mediaRepositoryProvider).continueWatching();
      if (mounted) setState(() => _continue = list);
    } catch (_) {}
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
              child: items.isEmpty && _continue.isEmpty
                  ? _empty()
                  : ListView(
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.only(bottom: 24, right: 16),
                      children: [
                        if (items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 24),
                            child: Text(
                              'Your library is empty. Add movies and series with the + button on their page.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          )
                        else
                          PagedPosterGrid(
                            itemCount: items.length,
                            rows: 2,
                            posterPath: (i) => items[i].posterPath,
                            itemBuilder: (context, i, lead, focusNode) {
                              final it = items[i];
                              final mi = MediaItem(
                                id: it.tmdbId,
                                mediaType: it.type,
                                title: it.type == 'movie' ? it.title : null,
                                name: it.type == 'tv' ? it.title : null,
                                posterPath: it.posterPath,
                              );
                              return FittedBox(
                                fit: BoxFit.contain,
                                child: PosterCard(
                                  item: mi,
                                  autofocus: lead,
                                  focusNode: focusNode,
                                  width: 132,
                                  ensureVisibleOnFocus: true,
                                  onTap: () =>
                                      openDetails(context, it.type, it.tmdbId),
                                ),
                              );
                            },
                          ),
                        if (_continue.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          ContinueWatchingRow(
                            title: 'Continue Watching',
                            items: _continue,
                            rows: 2,
                            autofocusFirst: items.isEmpty,
                            padding: EdgeInsets.zero,
                            onTap: (p) =>
                                openDetails(context, p.type, p.tmdbId),
                          ),
                        ],
                      ],
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

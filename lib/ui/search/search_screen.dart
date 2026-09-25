import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/focus.dart';
import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import '../../data/repository/media_repository.dart';
import '../../data/store/recommendation_seeds.dart';
import '../../data/tmdb/image_urls.dart';
import '../widgets/coming_soon_badge.dart';

enum _Status { idle, loading, empty, error, results }

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _fieldFocus = FocusNode();
  Timer? _debounce;
  _Status _status = _Status.idle;
  List<MediaItem> _results = [];
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fieldFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _status = _Status.idle);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _status = _Status.loading;
      _lastQuery = q;
    });
    try {
      final results = await ref.read(mediaRepositoryProvider).search(q);
      if (!mounted || _lastQuery != q) return;
      setState(() {
        _results = results;
        _status = results.isEmpty ? _Status.empty : _Status.results;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _Status.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final portrait = MediaQuery.of(context).orientation == Orientation.portrait;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FractionallySizedBox(
              widthFactor: portrait ? 1 : 0.55,
              alignment: Alignment.centerLeft,
              child: _searchField(),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FractionallySizedBox(
                widthFactor: portrait ? 1 : 0.6,
                alignment: Alignment.centerLeft,
                child: _content(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchField() {
    return DpadFieldFocus(
      child: TextField(
      controller: _controller,
      focusNode: _fieldFocus,
      onChanged: _onChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: 'Search movies & series…',
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.charcoalLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.textPrimary, width: 2),
        ),
      ),
      ),
    );
  }

  Widget _content() {
    switch (_status) {
      case _Status.idle:
        return const _Hint('Start typing to see suggestions');
      case _Status.loading:
        return const _Hint('Searching…');
      case _Status.empty:
        return _Hint('No results for "$_lastQuery"');
      case _Status.error:
        return const _Hint('Something went wrong. Try again.');
      case _Status.results:
        return ListView.separated(
          // Don't clip the focused row's border/scale at the left/right edges.
          clipBehavior: Clip.none,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          itemCount: _results.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final item = _results[i];
            return _SuggestionRow(
              item: item,
              onTap: () {
                final type = item.resolvedType('movie');
                RecommendationSeeds.record(type, item.id);
                openDetails(context, type, item.id);
              },
            );
          },
        );
    }
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text, style: const TextStyle(color: AppColors.textSecondary)),
      );
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.item, required this.onTap});
  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = thumbPosterUrl(item.posterPath);
    final type = item.resolvedType('movie');
    final subtitle = [
      if (item.year != null) item.year!,
      type == 'tv' ? 'Series' : 'Movie',
    ].join('  ·  ');
    return FocusableCard(
      onTap: onTap,
      focusedScale: 1.02,
      borderWidth: 2,
      ensureVisibleOnFocus: true,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: AppColors.charcoalLight,
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 40,
                height: 58,
                child: url != null
                    ? CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        memCacheWidth:
                            (40 * MediaQuery.devicePixelRatioOf(context)).round(),
                      )
                    : Container(color: AppColors.charcoal),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (item.comingSoon) ...[
                        const SizedBox(width: 8),
                        const ComingSoonBadge(),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

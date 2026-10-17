import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/focus.dart';
import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../data/helper/helper_query.dart';
import '../../data/models/media_item.dart';
import '../../data/repository/media_repository.dart';
import '../../data/store/recommendation_seeds.dart';
import '../../data/tmdb/image_urls.dart';
import '../widgets/coming_soon_badge.dart';
import '../widgets/watched_check.dart';

/// Ready-made phrases. The first one takes focus so a remote never opens
/// inside the keyboard.
const helperIdeas = <String>[
  'Disturbing movies',
  'Feel-good movies',
  'Mind-bending movies',
  'Sad movies',
  'Korean thrillers',
  'Scary movies',
  'Funny series',
  'Animated movies',
  'Crime series',
  '90s action movies',
  'Movies like Inception',
];

enum _Status { idle, loading, empty, error, results }

/// Survives leaving Helper for a title, so Back can show the same list.
class HelperMemory {
  static String query = '';
  static String note = '';
  static List<MediaItem> results = const [];
  static bool hasMore = false;

  static void save({
    required String query,
    required String note,
    required List<MediaItem> results,
    required bool hasMore,
  }) {
    HelperMemory.query = query;
    HelperMemory.note = note;
    HelperMemory.results = List.of(results);
    HelperMemory.hasMore = hasMore;
  }
}

class HelperScreen extends ConsumerStatefulWidget {
  const HelperScreen({super.key});

  @override
  ConsumerState<HelperScreen> createState() => _HelperScreenState();
}

class _HelperScreenState extends ConsumerState<HelperScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _fieldFocus = FocusNode(debugLabel: 'helper-field');
  final FocusNode _findNode = FocusNode(debugLabel: 'helper-find');
  final FocusNode _moreNode = FocusNode(debugLabel: 'helper-more');
  late final List<FocusNode> _ideaNodes = [
    for (var i = 0; i < helperIdeas.length; i++)
      FocusNode(debugLabel: 'helper-idea-$i'),
  ];
  List<FocusNode> _resultNodes = [];

  _Status _status = _Status.idle;
  List<MediaItem> _results = [];
  String _note = '';
  String _query = '';
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _moreArmed = true;
  int _searchGen = 0;

  @override
  void initState() {
    super.initState();
    if (HelperMemory.query.isNotEmpty && HelperMemory.results.isNotEmpty) {
      _controller.text = HelperMemory.query;
      _query = HelperMemory.query;
      _note = HelperMemory.note;
      _hasMore = HelperMemory.hasMore;
      _results = List.of(HelperMemory.results);
      _status = _Status.results;
      _swapResults(_results);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _fieldFocus.dispose();
    _findNode.dispose();
    _moreNode.dispose();
    for (final n in _ideaNodes) {
      n.dispose();
    }
    for (final n in _resultNodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _run(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    final request = parseHelperQuery(query);
    if (request == null) {
      _swapResults(const []);
      setState(() {
        _status = _Status.empty;
        _results = [];
        _query = '';
        _hasMore = false;
        _loadingMore = false;
        _note = 'Try a mood, a genre, or “movies like …”';
      });
      return;
    }
    final gen = ++_searchGen;
    setState(() {
      _status = _Status.loading;
      _note = 'Looking…';
      _hasMore = false;
      _loadingMore = false;
    });
    try {
      final feed =
          await ref.read(mediaRepositoryProvider).findByDescription(query);
      if (!mounted || gen != _searchGen) return;
      _swapResults(feed.items);
      setState(() {
        _results = feed.items;
        _query = query;
        _hasMore = feed.hasMore;
        _status = feed.items.isEmpty ? _Status.empty : _Status.results;
        _note = feed.items.isEmpty
            ? 'Nothing matched “$query”'
            : '${request.summary}  ·  ${request.explained}';
      });
      HelperMemory.save(
        query: query,
        note: _note,
        results: feed.items,
        hasMore: feed.hasMore,
      );
      if (feed.items.isNotEmpty) {
        final generation = gen;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _searchGen || _resultNodes.isEmpty) {
            return;
          }
          _resultNodes.first.requestFocus();
        });
      }
    } catch (_) {
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _status = _Status.error;
        _note = 'Something went wrong. Try again.';
      });
    }
  }

  void _onMoreFocused(bool focused) {
    if (!focused) {
      _moreArmed = true;
      return;
    }
    if (!_moreArmed || _loadingMore) return;
    _moreArmed = false;
    _more();
  }

  Future<void> _more() async {
    if (_loadingMore || !_hasMore || _query.isEmpty) return;
    final gen = _searchGen;
    final start = _results.length;
    setState(() => _loadingMore = true);
    try {
      final feed =
          await ref.read(mediaRepositoryProvider).moreByDescription(_query);
      if (!mounted || gen != _searchGen) return;
      _appendNodes(feed.items);
      setState(() {
        _results = feed.items;
        _hasMore = feed.hasMore;
        _loadingMore = false;
      });
      HelperMemory.save(
        query: _query,
        note: _note,
        results: feed.items,
        hasMore: feed.hasMore,
      );
      final focusAt = feed.items.length > start
          ? start
          : _resultNodes.isEmpty
              ? -1
              : _resultNodes.length - 1;
      if (focusAt >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || gen != _searchGen) return;
          if (focusAt >= _resultNodes.length) return;
          _resultNodes[focusAt].requestFocus();
        });
      }
    } catch (_) {
      if (!mounted || gen != _searchGen) return;
      setState(() => _loadingMore = false);
    }
  }

  void _appendNodes(List<MediaItem> items) {
    for (var i = _resultNodes.length; i < items.length; i++) {
      _resultNodes.add(FocusNode(debugLabel: 'helper-result-$i'));
    }
  }

  void _swapResults(List<MediaItem> items) {
    for (final n in _resultNodes) {
      n.dispose();
    }
    _resultNodes = [
      for (var i = 0; i < items.length; i++)
        FocusNode(debugLabel: 'helper-result-$i'),
    ];
  }

  void _open(MediaItem item) {
    final type = item.resolvedType('movie');
    RecommendationSeeds.record(type, item.id);
    openDetails(context, type, item.id);
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
            const Text(
              'Helper',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pick a list, or describe what you want',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            FractionallySizedBox(
              widthFactor: portrait ? 1 : 0.55,
              alignment: Alignment.centerLeft,
              child: _field(),
            ),
            const SizedBox(height: 10),
            FractionallySizedBox(
              widthFactor: portrait ? 1 : 0.55,
              alignment: Alignment.centerLeft,
              child: _findButton(),
            ),
            if (_note.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _note,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: FractionallySizedBox(
                widthFactor: portrait ? 1 : 0.6,
                alignment: Alignment.centerLeft,
                child: _list(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field() {
    return DpadFieldFocus(
      child: TextField(
        controller: _controller,
        focusNode: _fieldFocus,
        textInputAction: TextInputAction.search,
        onSubmitted: _run,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Disturbing movies, Korean thrillers…',
          hintStyle: const TextStyle(color: AppColors.textSecondary),
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

  Widget _findButton() {
    return FocusableCard(
      focusNode: _findNode,
      onTap: () => _run(_controller.text),
      focusedScale: 1.02,
      borderWidth: 2,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: AppColors.charcoalLight,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: const Row(
          children: [
            Icon(Icons.search, color: AppColors.textPrimary, size: 20),
            SizedBox(width: 10),
            Text(
              'Find',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    final showResults = _status == _Status.results && _results.isNotEmpty;
    final tiles = <Widget>[
      if (showResults) ...[
        const _SectionLabel('Results'),
        for (var i = 0; i < _results.length; i++)
          _TitleRow(
            item: _results[i],
            focusNode: _resultNodes[i],
            onTap: () => _open(_results[i]),
          ),
        if (_hasMore)
          _SeeMoreRow(
            focusNode: _moreNode,
            loading: _loadingMore,
            onTap: _more,
            onFocus: _onMoreFocused,
          ),
        const _SectionLabel('More ideas'),
      ] else
        const _SectionLabel('Try one'),
      for (var i = 0; i < helperIdeas.length; i++)
        _IdeaRow(
          label: helperIdeas[i],
          focusNode: _ideaNodes[i],
          autofocus: i == 0 && _status != _Status.results,
          onTap: () {
            _controller.text = helperIdeas[i];
            _run(helperIdeas[i]);
          },
        ),
    ];

    return ListView.separated(
      clipBehavior: Clip.none,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: tiles.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => tiles[i],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _IdeaRow extends StatelessWidget {
  const _IdeaRow({
    required this.label,
    required this.focusNode,
    required this.onTap,
    this.autofocus = false,
  });

  final String label;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: onTap,
      focusedScale: 1.02,
      borderWidth: 2,
      ensureVisibleOnFocus: true,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: AppColors.charcoalLight,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_outlined,
                color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeeMoreRow extends StatelessWidget {
  const _SeeMoreRow({
    required this.focusNode,
    required this.loading,
    required this.onTap,
    required this.onFocus,
  });

  final FocusNode focusNode;
  final bool loading;
  final VoidCallback onTap;
  final ValueChanged<bool> onFocus;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      focusNode: focusNode,
      onTap: loading ? null : onTap,
      onFocusChange: onFocus,
      focusedScale: 1.02,
      borderWidth: 2,
      ensureVisibleOnFocus: true,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: AppColors.charcoalLight,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(
              loading ? Icons.hourglass_top : Icons.add,
              color: AppColors.textPrimary,
              size: 18,
            ),
            const SizedBox(width: 12),
            Text(
              loading ? 'Adding more…' : 'See more',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.item,
    required this.focusNode,
    required this.onTap,
  });

  final MediaItem item;
  final FocusNode focusNode;
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
      focusNode: focusNode,
      onTap: onTap,
      focusedScale: 1.02,
      borderWidth: 2,
      ensureVisibleOnFocus: true,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: AppColors.charcoalLight,
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              height: 68,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: url != null
                        ? CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            memCacheWidth: (46 *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round(),
                          )
                        : Container(color: AppColors.charcoal),
                  ),
                  if (type == 'movie')
                    Positioned(
                      top: 3,
                      right: 3,
                      child: MovieWatchedBadge(tmdbId: item.id, size: 16),
                    ),
                ],
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
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
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

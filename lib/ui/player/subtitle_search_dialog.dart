import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/focus.dart';
import '../../core/theme.dart';
import '../../data/subtitle/opensubtitles_client.dart';
import '../../data/subtitle/subtitle_search.dart';

/// A downloaded search hit, ready to save and play.
class SearchedSubtitle {
  final String fileId;
  final String label;
  final String? language;
  final String body;

  const SearchedSubtitle({
    required this.fileId,
    required this.label,
    required this.body,
    this.language,
  });
}

class _RememberedSubtitleSearch {
  final String query;
  final List<OpenSubtitleHit> hits;

  const _RememberedSubtitleSearch({required this.query, required this.hits});
}

/// Last results for a title, kept after the dialog closes or a track is picked
/// so opening search again does not spend another lookup.
final Map<String, _RememberedSubtitleSearch> _subtitleSearches = {};

String _subtitleSearchKey(String type, int tmdbId, int? season, int? episode) =>
    '$type-$tmdbId-s${season ?? 0}e${episode ?? 0}';

@visibleForTesting
void clearSubtitleSearchMemory() => _subtitleSearches.clear();

/// Keyword search. The field starts as `Title s01e01`. Down leaves the field,
/// and the Search button is focused so a remote can run it with one OK.
/// Reopening the dialog for the same title shows the last results.
Future<SearchedSubtitle?> showSubtitleSearchDialog(
  BuildContext context, {
  required String initialQuery,
  required String title,
  required int tmdbId,
  required String type,
  int? season,
  int? episode,
  OpenSubtitlesClient? client,
}) {
  return showDialog<SearchedSubtitle>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _SubtitleSearchDialog(
      initialQuery: initialQuery,
      title: title,
      tmdbId: tmdbId,
      type: type,
      season: season,
      episode: episode,
      client: client ?? OpenSubtitlesClient(),
    ),
  );
}

class _SubtitleSearchDialog extends StatefulWidget {
  const _SubtitleSearchDialog({
    required this.initialQuery,
    required this.title,
    required this.tmdbId,
    required this.type,
    required this.client,
    this.season,
    this.episode,
  });

  final String initialQuery;
  final String title;
  final int tmdbId;
  final String type;
  final int? season;
  final int? episode;
  final OpenSubtitlesClient client;

  @override
  State<_SubtitleSearchDialog> createState() => _SubtitleSearchDialogState();
}

class _SubtitleSearchDialogState extends State<_SubtitleSearchDialog> {
  late final TextEditingController _query;
  final FocusNode _searchFocus = FocusNode();
  List<OpenSubtitleHit> _hits = const [];
  bool _busy = false;
  String? _downloadingId;
  String? _error;
  bool _searched = false;

  String get _key => _subtitleSearchKey(
        widget.type,
        widget.tmdbId,
        widget.season,
        widget.episode,
      );

  @override
  void initState() {
    super.initState();
    final saved = _subtitleSearches[_key];
    _query = TextEditingController(text: saved?.query ?? widget.initialQuery);
    if (saved != null) {
      _hits = saved.hits;
      _searched = true;
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _remember(String query, List<OpenSubtitleHit> hits) {
    _subtitleSearches[_key] = _RememberedSubtitleSearch(query: query, hits: hits);
  }

  Future<void> _search() async {
    final queryText = _query.text;
    final parsed = parseSubtitleSearch(
      queryText,
      season: widget.season,
      episode: widget.episode,
    );
    if (parsed.q.isEmpty) {
      setState(() => _error = 'Enter a title to search.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final sameShow = widget.title.trim().isNotEmpty &&
        parsed.q.toLowerCase() == widget.title.trim().toLowerCase();
    try {
      final hits = await widget.client.search(
        query: parsed.q,
        season: parsed.season,
        episode: parsed.episode,
        tmdbId: sameShow ? widget.tmdbId : null,
        type: sameShow ? widget.type : null,
      );
      _remember(queryText, hits);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _searched = true;
        _hits = hits;
      });
    } on OpenSubtitlesException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _searched = true;
        _error = e.message;
      });
    }
  }

  Future<void> _pick(OpenSubtitleHit hit) async {
    if (_downloadingId != null) return;
    setState(() {
      _downloadingId = hit.fileId;
      _error = null;
    });
    try {
      final body = await widget.client.downloadSrt(hit.fileId);
      if (!mounted) return;
      Navigator.pop(
        context,
        SearchedSubtitle(
          fileId: hit.fileId,
          label: hit.label,
          language: hit.language,
          body: body,
        ),
      );
    } on OpenSubtitlesException catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingId = null;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Align(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
            child: Material(
              color: AppColors.charcoalLight,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Search SRT',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close,
                              color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: DpadFieldFocus(
                        child: TextField(
                          controller: _query,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _search(),
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            hintText: 'Title',
                            hintStyle:
                                TextStyle(color: AppColors.textSecondary),
                            isDense: true,
                            filled: true,
                            fillColor: AppColors.charcoal,
                            border: OutlineInputBorder(
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _SearchButton(
                        focusNode: _searchFocus,
                        busy: _busy,
                        onTap: _busy ? null : _search,
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10, right: 8),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFFF6B6B),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Expanded(child: _results()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _results() {
    if (_busy) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (!_searched) {
      return const Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.only(right: 8, top: 8),
          child: Text(
            'Search uses this title. Change it if you want a different release.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      );
    }
    if (_hits.isEmpty) {
      return const Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'No subtitles found.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _hits.length,
      itemBuilder: (context, i) {
        final hit = _hits[i];
        final waiting = _downloadingId == hit.fileId;
        return _ResultRow(
          label: waiting ? 'Loading…' : hit.label,
          detail: hit.detail.isEmpty ? null : hit.detail,
          autofocus: i == 0,
          onTap: () => _pick(hit),
        );
      },
    );
  }
}

class _SearchButton extends StatefulWidget {
  const _SearchButton({
    required this.focusNode,
    required this.busy,
    required this.onTap,
  });

  final FocusNode focusNode;
  final bool busy;
  final VoidCallback? onTap;

  @override
  State<_SearchButton> createState() => _SearchButtonState();
}

class _SearchButtonState extends State<_SearchButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final fg = _focused ? Colors.black : AppColors.charcoal;
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: true,
      onFocusChange: (f) => setState(() => _focused = f),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap?.call();
          return null;
        }),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          decoration: BoxDecoration(
            color: _focused ? AppColors.focusRing : AppColors.textPrimary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.busy ? 'Searching…' : 'Search',
            style: TextStyle(color: fg, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatefulWidget {
  const _ResultRow({
    required this.label,
    required this.onTap,
    this.detail,
    this.autofocus = false,
  });

  final String label;
  final String? detail;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final fg = _focused ? Colors.black : AppColors.textPrimary;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        }),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: _focused ? AppColors.focusRing : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontSize: 15),
              ),
              if (widget.detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    widget.detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _focused ? Colors.black87 : AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

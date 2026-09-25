import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'watch_progress.dart';

/// A title the user saved to their Library. Stored locally (no account needed).
/// When accounts/sync land later this maps 1:1 to the server `library` doc.
class LibraryItem {
  final int tmdbId;
  final String type; // 'movie' | 'tv'
  final String? title;
  final String? posterPath;
  final int addedAt; // epoch millis

  const LibraryItem({
    required this.tmdbId,
    required this.type,
    this.title,
    this.posterPath,
    this.addedAt = 0,
  });

  Map<String, dynamic> toJson() => {
        'tmdbId': tmdbId,
        'type': type,
        'title': title,
        'posterPath': posterPath,
        'addedAt': addedAt,
      };

  factory LibraryItem.fromJson(Map<String, dynamic> j) => LibraryItem(
        tmdbId: j['tmdbId'] as int,
        type: j['type'] as String,
        title: j['title'] as String?,
        posterPath: j['posterPath'] as String?,
        addedAt: (j['addedAt'] as int?) ?? 0,
      );
}

/// Local "My Library". Mirrors [WatchProgressStore]'s shape (shared_preferences
/// + a [revision] notifier) so screens refresh reactively.
class LibraryStore {
  static const String _prefix = 'lib_';
  static late SharedPreferences _prefs;

  /// Bumped on every add/remove so the Library screen + the details toggle
  /// rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Optional sync hooks, set by SyncService. Fired AFTER a local write so a
  /// signed-in user's change can be pushed to their account.
  static void Function(LibraryItem it)? onAdded;
  static void Function(String type, int tmdbId)? onRemoved;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String _key(String type, int tmdbId) => '$_prefix$type-$tmdbId';

  static bool contains(String type, int tmdbId) =>
      _prefs.containsKey(_key(type, tmdbId));

  static void add(LibraryItem it) {
    final item = it.addedAt == 0
        ? LibraryItem(
            tmdbId: it.tmdbId,
            type: it.type,
            title: it.title,
            posterPath: it.posterPath,
            addedAt: DateTime.now().millisecondsSinceEpoch,
          )
        : it;
    _prefs.setString(_key(item.type, item.tmdbId), jsonEncode(item.toJson()));
    revision.value++;
    onAdded?.call(item);
  }

  static void remove(String type, int tmdbId) {
    _prefs.remove(_key(type, tmdbId));
    revision.value++;
    onRemoved?.call(type, tmdbId);
  }

  /// Adds if absent, removes if present. Returns the resulting membership.
  static bool toggle(LibraryItem it) {
    if (contains(it.type, it.tmdbId)) {
      remove(it.type, it.tmdbId);
      return false;
    }
    add(it);
    return true;
  }

  /// The most recent moment this title was watched (from watch progress),
  /// falling back to when it was added — the Library's sort key.
  static int _lastWatched(LibraryItem it) {
    final w = WatchProgressStore.get(it.type, it.tmdbId)?.updatedAt ?? 0;
    return w > it.addedAt ? w : it.addedAt;
  }

  /// All saved items, most-recently-watched first.
  static List<LibraryItem> all() {
    final items = _prefs
        .getKeys()
        .where((k) => k.startsWith(_prefix))
        .map((k) {
          final s = _prefs.getString(k);
          if (s == null) return null;
          try {
            return LibraryItem.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<LibraryItem>()
        .toList();
    items.sort((a, b) => _lastWatched(b).compareTo(_lastWatched(a)));
    return items;
  }
}

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
  final int updatedAt; // epoch millis, last-write-wins across devices
  final bool deleted;

  const LibraryItem({
    required this.tmdbId,
    required this.type,
    this.title,
    this.posterPath,
    this.addedAt = 0,
    this.updatedAt = 0,
    this.deleted = false,
  });

  Map<String, dynamic> toJson() => {
        'tmdbId': tmdbId,
        'type': type,
        'title': title,
        'posterPath': posterPath,
        'addedAt': addedAt,
        'updatedAt': updatedAt,
        'deleted': deleted,
      };

  factory LibraryItem.fromJson(Map<String, dynamic> j) => LibraryItem(
        tmdbId: (j['tmdbId'] as num).toInt(),
        type: j['type'] as String,
        title: j['title'] as String?,
        posterPath: j['posterPath'] as String?,
        addedAt: (j['addedAt'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
        deleted: (j['deleted'] as bool?) ?? false,
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
  static void Function(String type, int tmdbId, int updatedAt)? onRemoved;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String _key(String type, int tmdbId) => '$_prefix$type-$tmdbId';

  static LibraryItem? get(String type, int tmdbId) {
    final s = _prefs.getString(_key(type, tmdbId));
    if (s == null) return null;
    try {
      return LibraryItem.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static bool contains(String type, int tmdbId) {
    final it = get(type, tmdbId);
    return it != null && !it.deleted;
  }

  static void _write(LibraryItem item) {
    _prefs.setString(_key(item.type, item.tmdbId), jsonEncode(item.toJson()));
    revision.value++;
  }

  /// Writes a record from the account without echoing it back to the server.
  static void applyRemote(LibraryItem it) => _write(it);

  static void add(LibraryItem it) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final item = LibraryItem(
      tmdbId: it.tmdbId,
      type: it.type,
      title: it.title,
      posterPath: it.posterPath,
      addedAt: it.addedAt == 0 ? now : it.addedAt,
      updatedAt: it.updatedAt == 0 ? now : it.updatedAt,
    );
    _write(item);
    onAdded?.call(item);
  }

  static void remove(String type, int tmdbId) {
    final prev = get(type, tmdbId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final item = LibraryItem(
      tmdbId: tmdbId,
      type: type,
      title: prev?.title,
      posterPath: prev?.posterPath,
      addedAt: (prev?.addedAt ?? 0) == 0 ? now : prev!.addedAt,
      updatedAt: now,
      deleted: true,
    );
    _write(item);
    onRemoved?.call(type, tmdbId, now);
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

  static List<LibraryItem> _readAll() {
    return _prefs
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
  }

  /// Saved and removed titles. Removals stay as tombstones so another device
  /// can learn about them.
  static List<LibraryItem> every() => _readAll();

  /// All saved items, most-recently-watched first.
  static List<LibraryItem> all() {
    final items = _readAll().where((it) => !it.deleted).toList();
    items.sort((a, b) => _lastWatched(b).compareTo(_lastWatched(a)));
    return items;
  }
}

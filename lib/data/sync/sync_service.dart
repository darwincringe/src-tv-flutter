import 'package:dio/dio.dart';

import '../../core/router.dart';
import '../auth/auth_service.dart';
import '../store/library_store.dart';
import '../store/watch_progress.dart';

/// Bridges the local stores to the signed-in user's account.
///
/// Design: the local stores stay the source of truth / offline cache; the
/// server is last-write-wins by `updatedAt`. Everything here is best-effort —
/// network errors never throw into the UI (the one exception is [pushAllLocal],
/// which returns a success flag so the "sync my data" prompt can report).
///
/// When signed out, all of this is inert: the hooks bail immediately, so the
/// app behaves exactly as before (fully functional on local data alone).
class SyncService {
  /// True while [pullAll] is writing server data into the local stores, so the
  /// store hooks don't echo those writes straight back to the server.
  static bool _pulling = false;

  /// Wire the local-store hooks to push individual changes as they happen.
  /// Call once at startup (after the stores + AuthService are initialised).
  static void init() {
    WatchProgressStore.onSaved = (p) {
      if (_pulling || !AuthService.isSignedIn) return;
      _push('progress', _progressJson(p), put: true);
    };
    WatchProgressStore.onRemoved = (type, id) {
      if (_pulling || !AuthService.isSignedIn) return;
      _remove('progress/$type/$id');
    };
    LibraryStore.onAdded = (it) {
      if (_pulling || !AuthService.isSignedIn) return;
      _push('library', _libraryJson(it));
    };
    LibraryStore.onRemoved = (type, id) {
      if (_pulling || !AuthService.isSignedIn) return;
      _remove('library/$type/$id');
    };
  }

  // ---- field mapping (local model <-> API shape) -------------------------

  static Map<String, dynamic> _progressJson(WatchProgress p) => {
        'mediaType': p.type,
        'tmdbId': p.tmdbId,
        'season': p.season,
        'episode': p.episode,
        'positionMs': p.positionMs,
        'durationMs': p.durationMs,
        'completed': p.completed,
        'title': p.title,
        'posterPath': p.posterPath,
        // Never send 0 — the server would treat it as the oldest possible write
        // and any real record would win, but a real timestamp keeps LWW honest.
        'updatedAt': p.updatedAt == 0
            ? DateTime.now().millisecondsSinceEpoch
            : p.updatedAt,
      };

  static WatchProgress _progressFrom(Map<String, dynamic> d) => WatchProgress(
        tmdbId: (d['tmdbId'] as num).toInt(),
        type: (d['mediaType'] as String?) ?? 'movie',
        season: (d['season'] as num?)?.toInt(),
        episode: (d['episode'] as num?)?.toInt(),
        positionMs: (d['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (d['durationMs'] as num?)?.toInt() ?? 0,
        updatedAt: (d['updatedAt'] as num?)?.toInt() ?? 0,
        title: d['title'] as String?,
        posterPath: d['posterPath'] as String?,
        completed: (d['completed'] as bool?) ?? false,
      );

  static Map<String, dynamic> _libraryJson(LibraryItem it) {
    final watched = WatchProgressStore.get(it.type, it.tmdbId)?.updatedAt ?? 0;
    return {
      'mediaType': it.type,
      'tmdbId': it.tmdbId,
      'title': it.title,
      'posterPath': it.posterPath,
      'lastWatchedAt': watched > it.addedAt ? watched : it.addedAt,
    };
  }

  static LibraryItem _libraryFrom(Map<String, dynamic> d) => LibraryItem(
        tmdbId: (d['tmdbId'] as num).toInt(),
        type: (d['mediaType'] as String?) ?? 'movie',
        title: d['title'] as String?,
        posterPath: d['posterPath'] as String?,
        addedAt: (d['addedAt'] as num?)?.toInt() ?? 0,
      );

  // ---- single-item push (from the store hooks) ---------------------------

  static Future<void> _push(
    String path,
    Map<String, dynamic> body, {
    bool put = false,
  }) async {
    try {
      final opts = AuthService.authOptions();
      if (put) {
        await AuthService.dio.put(path, data: body, options: opts);
      } else {
        await AuthService.dio.post(path, data: body, options: opts);
      }
    } catch (e) {
      // A stored session the server no longer accepts (expired or signed with
      // an old secret) must be dropped, or playback keeps retrying it.
      await _dropIfUnauthorized(e);
    }
  }

  static Future<void> _remove(String path) async {
    try {
      await AuthService.dio.delete(path, options: AuthService.authOptions());
    } catch (e) {
      await _dropIfUnauthorized(e);
    }
  }

  /// 401 means this device's saved token is dead. Sign out and open the account
  /// screen, which shows the login form when there is no session.
  static Future<void> _dropIfUnauthorized(Object e) async {
    if (e is! DioException || e.response?.statusCode != 401) return;
    if (!AuthService.isSignedIn) return;
    await AuthService.signOut();
    appRouter.go('/settings');
  }

  // ---- bulk sync (used by the post-auth flow) ----------------------------

  /// Upload ALL local progress + library to the account. Returns true on
  /// success. Used by the "save this device's data to your account" prompt.
  static Future<bool> pushAllLocal() async {
    if (!AuthService.isSignedIn) return false;
    try {
      final records = WatchProgressStore.all().map(_progressJson).toList();
      if (records.isNotEmpty) {
        await AuthService.dio.post(
          'progress/batch',
          data: {'records': records},
          options: AuthService.authOptions(),
        );
      }
      for (final it in LibraryStore.all()) {
        await AuthService.dio.post(
          'library',
          data: _libraryJson(it),
          options: AuthService.authOptions(),
        );
      }
      return true;
    } catch (e) {
      await _dropIfUnauthorized(e);
      return false;
    }
  }

  /// Pull the account's progress + library into the local stores
  /// (last-write-wins). Local writes made here are suppressed from echoing
  /// back to the server. Best-effort: returns quietly on any error.
  static Future<void> pullAll() async {
    if (!AuthService.isSignedIn) return;
    _pulling = true;
    try {
      final pr = await AuthService.dio.get(
        'progress',
        options: AuthService.authOptions(),
      );
      if (pr.data is List) {
        for (final d in (pr.data as List)) {
          if (d is! Map) continue;
          final remote = _progressFrom(Map<String, dynamic>.from(d));
          final local = WatchProgressStore.get(remote.type, remote.tmdbId);
          if (local == null || remote.updatedAt >= local.updatedAt) {
            WatchProgressStore.save(remote);
          }
        }
      }
      final lr = await AuthService.dio.get(
        'library',
        options: AuthService.authOptions(),
      );
      if (lr.data is List) {
        for (final d in (lr.data as List)) {
          if (d is! Map) continue;
          final it = _libraryFrom(Map<String, dynamic>.from(d));
          if (!LibraryStore.contains(it.type, it.tmdbId)) {
            LibraryStore.add(it);
          }
        }
      }
    } catch (e) {
      // Offline / server hiccup — local stays as-is; a later start retries.
      // A 401 is not a hiccup: the saved token is rejected, so end the session.
      await _dropIfUnauthorized(e);
    } finally {
      _pulling = false;
    }
  }
}

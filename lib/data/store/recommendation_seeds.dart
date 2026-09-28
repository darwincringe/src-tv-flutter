import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A recommendation seed: a title the user watched or opened from search.
class Seed {
  final String type;
  final int id;
  final int recordedAt;

  const Seed(this.type, this.id, {this.recordedAt = 0});

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'recordedAt': recordedAt,
      };

  factory Seed.fromJson(Map<String, dynamic> j) => Seed(
        j['type'] as String,
        (j['id'] as num).toInt(),
        recordedAt: (j['recordedAt'] as num?)?.toInt() ?? 0,
      );
}

/// Stores up to [max] recent seeds (newest-first) in a single JSON list.
/// Mirrors the Kotlin `RecommendationSeeds`.
class RecommendationSeeds {
  static const String _key = 'reco_seeds_list';
  static const int max = 30;
  static late SharedPreferences _prefs;

  /// Bumped whenever the seed list changes so Recommended can reload.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Fired when this device records a new seed, so it can be pushed.
  static void Function(Seed seed)? onRecorded;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static void _write(List<Seed> seeds) {
    final capped = seeds.take(max).toList();
    _prefs.setString(
      _key,
      jsonEncode(capped.map((s) => s.toJson()).toList()),
    );
    revision.value++;
  }

  static void record(String type, int id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final list = all()..removeWhere((s) => s.type == type && s.id == id);
    final seed = Seed(type, id, recordedAt: now);
    list.insert(0, seed);
    _write(list);
    onRecorded?.call(seed);
  }

  /// Replaces the list with a merged account copy. Does not push.
  static void replace(List<Seed> seeds) {
    final sorted = [...seeds]..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final prev = all();
    if (sorted.length == prev.length) {
      var same = true;
      for (var i = 0; i < sorted.length; i++) {
        if (sorted[i].type != prev[i].type ||
            sorted[i].id != prev[i].id ||
            sorted[i].recordedAt != prev[i].recordedAt) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    _write(sorted);
  }

  /// Gives undated local seeds a time so they can merge with other devices
  /// without jumping ahead of everything recorded today.
  static void stampMissingTimes() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final list = all();
    if (list.every((s) => s.recordedAt > 0)) return;
    var older = 0;
    _write([
      for (final s in list)
        s.recordedAt > 0
            ? s
            : Seed(s.type, s.id, recordedAt: now - (++older) * 1000),
    ]);
  }

  static List<Seed> all() {
    final s = _prefs.getString(_key);
    if (s == null) return [];
    try {
      final data = jsonDecode(s) as List;
      return data
          .map((e) => Seed.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

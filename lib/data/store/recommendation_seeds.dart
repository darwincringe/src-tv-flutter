import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A recommendation seed: a title the user watched or opened from search.
class Seed {
  final String type;
  final int id;
  const Seed(this.type, this.id);

  Map<String, dynamic> toJson() => {'type': type, 'id': id};

  factory Seed.fromJson(Map<String, dynamic> j) =>
      Seed(j['type'] as String, j['id'] as int);
}

/// Stores up to [max] recent seeds (newest-first) in a single JSON list.
/// Mirrors the Kotlin `RecommendationSeeds`.
class RecommendationSeeds {
  static const String _key = 'reco_seeds_list';
  static const int max = 30;
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static void record(String type, int id) {
    final list = all()..removeWhere((s) => s.type == type && s.id == id);
    list.insert(0, Seed(type, id));
    final capped = list.take(max).toList();
    _prefs.setString(
      _key,
      jsonEncode(capped.map((s) => s.toJson()).toList()),
    );
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

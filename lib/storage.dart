import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Plans live in SharedPreferences as one JSON array — small, synchronous to
/// read, and works identically on Android and on the web build.
class PlanStore {
  static const String _key = 'board.plans.v1';

  Future<List<BoardPlan>> loadAll() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <BoardPlan>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      final List<BoardPlan> plans = list
          .map((dynamic e) => BoardPlan.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      plans.sort((BoardPlan a, BoardPlan b) => b.updatedAt.compareTo(a.updatedAt));
      return plans;
    } catch (_) {
      return <BoardPlan>[];
    }
  }

  Future<void> saveAll(List<BoardPlan> plans) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(plans.map((BoardPlan p) => p.toJson()).toList());
    await prefs.setString(_key, raw);
  }

  Future<void> save(BoardPlan plan) async {
    final List<BoardPlan> plans = await loadAll();
    final int index = plans.indexWhere((BoardPlan p) => p.id == plan.id);
    if (index >= 0) {
      plans[index] = plan;
    } else {
      plans.add(plan);
    }
    await saveAll(plans);
  }

  Future<void> delete(String id) async {
    final List<BoardPlan> plans = await loadAll();
    plans.removeWhere((BoardPlan p) => p.id == id);
    await saveAll(plans);
  }
}

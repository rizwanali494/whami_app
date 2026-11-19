import 'package:shared_preferences/shared_preferences.dart';

import '../models/flight_plan.dart';

/// Local persistence for the active flight plan (survives restart).
class FlightPlanStore {
  static const _keyActive = 'whami_active_flight_plan_v1';

  Future<FlightPlan?> loadActive() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyActive);
    if (raw == null || raw.isEmpty) return null;
    try {
      return FlightPlan.fromJsonString(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveActive(FlightPlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyActive,
      plan.copyWith(updatedAt: DateTime.now()).toJsonString(),
    );
  }

  Future<void> clearActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyActive);
  }
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide user preferences (units, outdoor mode, onboarding).
class AppPreferences extends ChangeNotifier {
  static const _kMetric = 'units_metric';
  static const _kOutdoor = 'outdoor_mode';
  static const _kOnboarding = 'onboarding_seen';

  SharedPreferences? _prefs;
  bool _useMetric = true;
  bool _outdoorMode = false;
  bool _onboardingSeen = false;
  bool _ready = false;

  bool get isReady => _ready;
  bool get useMetric => _useMetric;
  bool get outdoorMode => _outdoorMode;
  bool get onboardingSeen => _onboardingSeen;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _useMetric = _prefs!.getBool(_kMetric) ?? true;
    _outdoorMode = _prefs!.getBool(_kOutdoor) ?? false;
    _onboardingSeen = _prefs!.getBool(_kOnboarding) ?? false;
    _ready = true;
    notifyListeners();
  }

  Future<void> setUseMetric(bool value) async {
    _useMetric = value;
    await _prefs?.setBool(_kMetric, value);
    notifyListeners();
  }

  Future<void> setOutdoorMode(bool value) async {
    _outdoorMode = value;
    await _prefs?.setBool(_kOutdoor, value);
    notifyListeners();
  }

  Future<void> setOnboardingSeen(bool value) async {
    _onboardingSeen = value;
    await _prefs?.setBool(_kOnboarding, value);
    notifyListeners();
  }

  String formatDistance(double meters) {
    if (_useMetric) {
      if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
      return '${meters.round()} m';
    }
    final feet = meters * 3.28084;
    if (feet >= 5280) return '${(feet / 5280).toStringAsFixed(1)} mi';
    return '${feet.round()} ft';
  }
}

final appPreferences = AppPreferences();

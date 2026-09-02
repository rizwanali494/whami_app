import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WHAMI-Air research / advisory preferences.
class AirPreferences extends ChangeNotifier {
  static const _kAirMode = 'whami_air_mode';
  static const _kRecording = 'whami_air_recording';
  static const _kKp = 'whami_air_kp';
  static const _kEfb = 'whami_air_efb_layout';
  static const _kDisclaimerAccepted = 'whami_air_disclaimer_ok';

  SharedPreferences? _prefs;
  bool _airModeEnabled = false;
  bool _recordingEnabled = true;
  bool _efbLayout = false;
  bool _disclaimerAccepted = false;
  double _kpIndex = 3.0;
  bool _ready = false;

  bool get isReady => _ready;
  bool get airModeEnabled => _airModeEnabled;
  bool get recordingEnabled => _recordingEnabled;
  bool get efbLayout => _efbLayout;
  bool get disclaimerAccepted => _disclaimerAccepted;
  double get kpIndex => _kpIndex;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _airModeEnabled = _prefs!.getBool(_kAirMode) ?? false;
    _recordingEnabled = _prefs!.getBool(_kRecording) ?? true;
    _efbLayout = _prefs!.getBool(_kEfb) ?? false;
    _disclaimerAccepted = _prefs!.getBool(_kDisclaimerAccepted) ?? false;
    _kpIndex = _prefs!.getDouble(_kKp) ?? 3.0;
    _ready = true;
    notifyListeners();
  }

  Future<void> setAirModeEnabled(bool value) async {
    _airModeEnabled = value;
    await _prefs?.setBool(_kAirMode, value);
    notifyListeners();
  }

  Future<void> setRecordingEnabled(bool value) async {
    _recordingEnabled = value;
    await _prefs?.setBool(_kRecording, value);
    notifyListeners();
  }

  Future<void> setEfbLayout(bool value) async {
    _efbLayout = value;
    await _prefs?.setBool(_kEfb, value);
    notifyListeners();
  }

  Future<void> setDisclaimerAccepted(bool value) async {
    _disclaimerAccepted = value;
    await _prefs?.setBool(_kDisclaimerAccepted, value);
    notifyListeners();
  }

  Future<void> setKpIndex(double value) async {
    _kpIndex = value.clamp(0.0, 9.0);
    await _prefs?.setDouble(_kKp, _kpIndex);
    notifyListeners();
  }
}

final airPreferences = AirPreferences();

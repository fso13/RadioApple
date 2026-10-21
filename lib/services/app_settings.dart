import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appSettings = AppSettings();

class AppSettings extends ChangeNotifier {
  static const _volumeKey = 'volume';
  static const _resumeKey = 'resume_last_station';
  static const _lastStationKey = 'last_station_id';
  static const _autoStartKey = 'auto_start';

  double _volume = 0.8;
  bool _resumeLastStation = false;
  String? _lastStationId;
  bool _autoStartEnabled = false;
  bool _loaded = false;

  double get volume => _volume;
  bool get resumeLastStation => _resumeLastStation;
  String? get lastStationId => _lastStationId;
  bool get autoStartEnabled => _autoStartEnabled;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _volume = (prefs.getDouble(_volumeKey) ?? 0.8).clamp(0.0, 1.0);
    _resumeLastStation = prefs.getBool(_resumeKey) ?? false;
    _lastStationId = prefs.getString(_lastStationKey);
    _autoStartEnabled = prefs.getBool(_autoStartKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeKey, _volume);
  }

  Future<void> setResumeLastStation(bool value) async {
    _resumeLastStation = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_resumeKey, value);
  }

  Future<void> setLastStationId(String? id) async {
    _lastStationId = id;
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_lastStationKey);
    } else {
      await prefs.setString(_lastStationKey, id);
    }
  }

  Future<void> setAutoStartEnabled(bool value) async {
    _autoStartEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoStartKey, value);
  }
}

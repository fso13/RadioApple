import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:radio_mac/models/equalizer_preset.dart';
import 'package:radio_mac/services/native_radio_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

final equalizerService = EqualizerService();

class EqualizerService extends ChangeNotifier {
  static const _enabledKey = 'eq_enabled';
  static const _presetKey = 'eq_preset';
  static const _gainsKey = 'eq_gains';
  static const _customKey = 'eq_custom_gains';

  bool _enabled = false;
  String _presetId = EqualizerCatalog.flatId;
  List<double> _gains = List<double>.filled(EqualizerCatalog.bandCount, 0);
  List<double> _customGains =
      List<double>.filled(EqualizerCatalog.bandCount, 0);
  Timer? _persistTimer;
  bool _loaded = false;

  bool get enabled => _enabled;
  String get presetId => _presetId;
  List<double> get gains => List.unmodifiable(_gains);
  bool get isCustom => _presetId == EqualizerCatalog.customId;
  bool get isLoaded => _loaded;

  EqualizerPreset get preset => EqualizerCatalog.byId(_presetId);

  Future<void> load() async {
    if (_loaded) {
      await _pushNative();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _presetId = prefs.getString(_presetKey) ?? EqualizerCatalog.flatId;
    _gains = _readGains(prefs, _gainsKey) ??
        EqualizerCatalog.clampGains(EqualizerCatalog.byId(_presetId).gains);
    _customGains = _readGains(prefs, _customKey) ?? List<double>.from(_gains);
    if (_presetId != EqualizerCatalog.customId) {
      _gains = EqualizerCatalog.clampGains(preset.gains);
    }
    _loaded = true;
    notifyListeners();
    await _pushNative();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    await NativeRadioPlayer.instance.setEqEnabled(value);
    await _persistNow();
  }

  Future<void> applyPreset(String id) async {
    _presetId = id;
    if (id == EqualizerCatalog.customId) {
      _gains = EqualizerCatalog.clampGains(_customGains);
    } else {
      _gains = EqualizerCatalog.clampGains(EqualizerCatalog.byId(id).gains);
    }
    notifyListeners();
    await NativeRadioPlayer.instance.setEqGains(_gains);
    await _persistNow();
  }

  Future<void> setBand(int index, double value) async {
    if (index < 0 || index >= _gains.length) return;
    _gains[index] = value.clamp(
      EqualizerCatalog.minGain,
      EqualizerCatalog.maxGain,
    );
    _presetId = EqualizerCatalog.customId;
    _customGains = List<double>.from(_gains);
    notifyListeners();
    await NativeRadioPlayer.instance.setEqGains(_gains);
    _schedulePersist();
  }

  Future<void> resetFlat() => applyPreset(EqualizerCatalog.flatId);

  Future<void> _pushNative() async {
    try {
      await NativeRadioPlayer.instance.setEqEnabled(_enabled);
      await NativeRadioPlayer.instance.setEqGains(_gains);
    } catch (_) {}
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), _persistNow);
  }

  Future<void> _persistNow() async {
    _persistTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, _enabled);
    await prefs.setString(_presetKey, _presetId);
    await prefs.setString(_gainsKey, jsonEncode(_gains));
    await prefs.setString(_customKey, jsonEncode(_customGains));
  }

  static List<double>? _readGains(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return EqualizerCatalog.clampGains(
        decoded.map((e) => (e as num).toDouble()).toList(),
      );
    } catch (_) {
      return null;
    }
  }
}

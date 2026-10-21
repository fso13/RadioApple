import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:radio_mac/data/default_stations.dart';
import 'package:radio_mac/models/radio_station.dart';
import 'package:radio_mac/services/logo_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

final stationLibrary = StationLibrary();

class StationLibrary extends ChangeNotifier {
  static const _prefsKey = 'stations_v1';
  static const _uuid = Uuid();

  final List<RadioStation> _stations = [];
  final Set<String> _resolving = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<RadioStation> get stations => List.unmodifiable(_stations);

  List<RadioStation> get favorites =>
      _stations.where((s) => s.isFavorite).toList();

  List<String> get genres {
    final names = <String>{};
    for (final station in _stations) {
      names.add(GenreCatalog.normalize(station.genre));
    }
    final ordered = [
      ...GenreCatalog.presets.where(names.contains),
      ...names.where((g) => !GenreCatalog.presets.contains(g)).toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
    ];
    return ordered;
  }

  RadioStation? byId(String id) {
    for (final station in _stations) {
      if (station.id == id) return station;
    }
    return null;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      _stations
        ..clear()
        ..addAll(DefaultStations.catalog);
      await _persist();
    } else {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _stations
          ..clear()
          ..addAll(
            decoded
                .whereType<Map>()
                .map((e) => RadioStation.fromJson(Map<String, dynamic>.from(e)))
                .where((s) => s.id.isNotEmpty && s.url.isNotEmpty),
          );
        if (_stations.isEmpty) {
          _stations.addAll(DefaultStations.catalog);
          await _persist();
        } else {
          await _mergeMissingBuiltIns();
          await _refreshBuiltInLogos();
        }
      } catch (_) {
        _stations
          ..clear()
          ..addAll(DefaultStations.catalog);
        await _persist();
      }
    }
    _loaded = true;
    notifyListeners();
    unawaited(resolveMissingLogos());
  }

  /// Adds newly shipped built-in stations without wiping user edits.
  Future<void> _mergeMissingBuiltIns() async {
    final existingIds = {for (final s in _stations) s.id};
    final missing = DefaultStations.catalog
        .where((s) => !existingIds.contains(s.id))
        .toList();
    if (missing.isEmpty) return;
    _stations.addAll(missing);
    await _persist();
  }

  Future<void> _refreshBuiltInLogos() async {
    final catalog = {for (final s in DefaultStations.catalog) s.id: s};
    var changed = false;
    for (var i = 0; i < _stations.length; i++) {
      final current = _stations[i];
      final shipped = catalog[current.id];
      if (shipped == null || !shipped.hasLogo) continue;
      if (current.hasLogo) continue;
      _stations[i] = current.copyWith(logoUrl: shipped.logoUrl);
      changed = true;
    }
    if (changed) await _persist();
  }

  Future<RadioStation> add({
    required String name,
    required String url,
    required String genre,
    String? comment,
    String? logoUrl,
  }) async {
    final station = RadioStation(
      id: _uuid.v4(),
      name: name.trim(),
      url: url.trim(),
      genre: GenreCatalog.normalize(genre),
      comment: _emptyToNull(comment),
      logoUrl: _emptyToNull(logoUrl),
    );
    _stations.add(station);
    await _persist();
    notifyListeners();
    if (!station.hasLogo) {
      unawaited(_resolveAndApply(station));
    }
    return station;
  }

  Future<void> applyResolvedLogo(String id, String logoUrl) async {
    final index = _stations.indexWhere((s) => s.id == id);
    if (index < 0) return;
    if (_stations[index].hasLogo) return;
    _stations[index] = _stations[index].copyWith(logoUrl: logoUrl);
    await _persist();
    notifyListeners();
  }

  Future<void> resolveMissingLogos() async {
    final missing = _stations.where((s) => !s.hasLogo).toList();
    for (final station in missing) {
      await _resolveAndApply(station);
    }
  }

  Future<void> _resolveAndApply(
    RadioStation station, {
    String? homepage,
  }) async {
    if (station.hasLogo || _resolving.contains(station.id)) return;
    _resolving.add(station.id);
    try {
      final logo = await LogoResolver.instance.resolve(
        streamUrl: station.url,
        homepage: homepage,
        name: station.name,
      );
      if (logo == null) return;
      await applyResolvedLogo(station.id, logo);
    } finally {
      _resolving.remove(station.id);
    }
  }

  Future<void> resolveFromHomepage(String id, String homepage) async {
    final station = byId(id);
    if (station == null || station.hasLogo) return;
    await _resolveAndApply(station, homepage: homepage);
  }

  Future<void> update(RadioStation updated) async {
    final index = _stations.indexWhere((s) => s.id == updated.id);
    if (index < 0) return;
    _stations[index] = updated.copyWith(
      genre: GenreCatalog.normalize(updated.genre),
      comment: _emptyToNull(updated.comment),
      logoUrl: _emptyToNull(updated.logoUrl),
      clearComment: _emptyToNull(updated.comment) == null,
      clearLogo: _emptyToNull(updated.logoUrl) == null,
    );
    await _persist();
    notifyListeners();
    if (_emptyToNull(updated.logoUrl) == null) {
      unawaited(_resolveAndApply(_stations[index]));
    }
  }

  Future<void> remove(String id) async {
    _stations.removeWhere((s) => s.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> toggleFavorite(String id) async {
    final index = _stations.indexWhere((s) => s.id == id);
    if (index < 0) return;
    _stations[index] =
        _stations[index].copyWith(isFavorite: !_stations[index].isFavorite);
    await _persist();
    notifyListeners();
  }

  Future<void> restoreDefaults() async {
    final custom = _stations.where((s) => !s.builtIn).toList();
    final favorites = {
      for (final s in _stations.where((s) => s.isFavorite)) s.id,
    };
    _stations
      ..clear()
      ..addAll(
        DefaultStations.catalog.map(
          (s) => s.copyWith(isFavorite: favorites.contains(s.id)),
        ),
      )
      ..addAll(custom);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_stations.map((s) => s.toJson()).toList()),
    );
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

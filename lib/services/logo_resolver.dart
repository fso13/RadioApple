import 'dart:convert';

import 'package:http/http.dart' as http;

/// Finds a station logo from the stream URL (and optional homepage / name).
///
/// Stream hosts are often CDNs, so the resolver:
/// 1. asks Radio Browser for a favicon matching the stream,
/// 2. tries the station homepage from ICY metadata,
/// 3. falls back to a favicon for the stream's brand domain.
class LogoResolver {
  LogoResolver({http.Client? client}) : _client = client ?? http.Client();

  static final instance = LogoResolver();

  static const _radioBrowser = 'https://de1.api.radio-browser.info';
  static const _userAgent = 'RadioMac/1.0';

  static const _cdnHosts = {
    'hostingradio.ru',
    'cdnvideo.ru',
    'streamguys1.com',
    'getradio.me',
    'mediacdn.ru',
    '101.ru',
    'amgradio.ru',
    'volna.top',
    'radio-holding.ru',
    'vdfm.ru',
  };

  final http.Client _client;

  Future<String?> resolve({
    required String streamUrl,
    String? homepage,
    String? name,
  }) async {
    final fromCatalog = await _fromRadioBrowser(
      streamUrl: streamUrl,
      name: name,
    );
    if (fromCatalog != null) return fromCatalog;

    final hosts = <String>[];
    final homeHost = hostOf(homepage);
    if (homeHost != null) hosts.add(homeHost);
    final brand = brandHost(hostOf(streamUrl));
    if (brand != null) hosts.add(brand);

    for (final host in hosts) {
      final viaGoogle =
          'https://www.google.com/s2/favicons?sz=128&domain=$host';
      if (await _looksLikeImage(viaGoogle)) return viaGoogle;
    }
    return null;
  }

  Future<String?> _fromRadioBrowser({
    required String streamUrl,
    String? name,
  }) async {
    final byUrl = await _searchRadioBrowser({'url': streamUrl});
    final fav = _bestFavicon(byUrl);
    if (fav != null) return fav;

    final trimmed = name?.trim();
    if (trimmed == null || trimmed.length < 3) return null;
    final byName = await _searchRadioBrowser({
      'name': trimmed,
      'countrycode': 'RU',
    });
    return _bestFavicon(byName);
  }

  Future<List<Map<String, dynamic>>> _searchRadioBrowser(
    Map<String, String> params,
  ) async {
    try {
      final uri = Uri.parse('$_radioBrowser/json/stations/search').replace(
        queryParameters: {
          ...params,
          'hidebroken': 'true',
          'order': 'clickcount',
          'reverse': 'true',
          'limit': '5',
        },
      );
      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String? _bestFavicon(List<Map<String, dynamic>> stations) {
    for (final station in stations) {
      final raw = (station['favicon'] as String?)?.trim();
      if (raw == null || raw.isEmpty || raw == 'null') continue;
      final uri = Uri.tryParse(raw);
      if (uri == null || !uri.hasScheme) continue;
      if (uri.scheme != 'http' && uri.scheme != 'https') continue;
      return raw;
    }
    return null;
  }

  Future<bool> _looksLikeImage(String url) async {
    try {
      final response = await _client
          .head(Uri.parse(url), headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 400) {
        return false;
      }
      final type = response.headers['content-type'] ?? '';
      return type.startsWith('image/');
    } catch (_) {
      return false;
    }
  }

  static String? hostOf(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return null;
    return uri.host.toLowerCase();
  }

  /// Drops CDN hosts; `ice1.somafm.com` → `somafm.com`.
  static String? brandHost(String? host) {
    if (host == null || host.isEmpty) return null;
    for (final cdn in _cdnHosts) {
      if (host == cdn || host.endsWith('.$cdn')) return null;
    }
    final parts = host.split('.');
    if (parts.length >= 2) {
      return '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
    }
    return host;
  }
}

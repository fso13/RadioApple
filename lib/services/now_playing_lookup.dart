import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:radio_mac/models/now_playing.dart';

/// Resolves the current track from station APIs, Icecast, or in-band ICY tags.
class NowPlayingLookup {
  NowPlayingLookup({http.Client? client}) : _client = client ?? http.Client();

  static final instance = NowPlayingLookup();

  static const _userAgent = 'RadioMac/1.0';
  static const _timeout = Duration(seconds: 8);

  final http.Client _client;
  final Map<String, String?> _artworkCache = {};

  Future<NowPlaying?> resolve({
    required String streamUrl,
    String? stationName,
    bool allowIcySidecar = true,
  }) async {
    final uri = Uri.tryParse(streamUrl);
    if (uri == null || uri.host.isEmpty) return null;

    final fromParadise = await _radioParadise(uri);
    if (fromParadise != null) return fromParadise;

    final fromSoma = await _somaFm(uri);
    if (fromSoma != null) return fromSoma;

    final fromIcecast = await _icecastStatus(uri, stationName: stationName);
    if (fromIcecast != null) return fromIcecast;

    if (!allowIcySidecar || _looksLikeHls(uri)) return null;
    return _icySidecar(uri, stationName: stationName);
  }

  Future<String?> artworkFor(NowPlaying track) async {
    if (track.hasArtwork) return track.artworkUrl;
    final who = track.displayArtist;
    final song = track.displayTitle;
    if (song.length < 3) return null;
    final query = [?who, song].join(' ');
    if (_artworkCache.containsKey(query)) return _artworkCache[query];

    final url = await _itunesArtwork(query);
    _artworkCache[query] = url;
    if (_artworkCache.length > 80) {
      _artworkCache.remove(_artworkCache.keys.first);
    }
    return url;
  }

  Future<NowPlaying?> _radioParadise(Uri stream) async {
    if (!stream.host.contains('radioparadise.com')) return null;
    final path = stream.path.toLowerCase();
    var chan = 0;
    if (path.contains('mellow')) {
      chan = 1;
    } else if (path.contains('rock')) {
      chan = 2;
    } else if (path.contains('global') || path.contains('world')) {
      chan = 3;
    }
    try {
      final uri = Uri.parse(
        'https://api.radioparadise.com/api/nowplaying_list?chan=$chan',
      );
      final response = await _get(uri);
      if (response == null) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final songWrap = decoded['song'];
      Map<String, dynamic>? song;
      if (songWrap is Map && songWrap['0'] is Map) {
        song = Map<String, dynamic>.from(songWrap['0'] as Map);
      }
      if (song == null) return null;
      final artist = (song['artist'] as String?)?.trim();
      final title = (song['title'] as String?)?.trim();
      if (title == null || title.isEmpty) return null;
      final cover = (song['cover'] as String?)?.trim();
      final artwork = (cover != null && cover.isNotEmpty)
          ? 'https://img.radioparadise.com/$cover'
          : null;
      final raw = [
        if (artist != null && artist.isNotEmpty) artist,
        title,
      ].join(' — ');
      return NowPlaying(
        raw: raw,
        artist: artist,
        title: title,
        album: (song['album'] as String?)?.trim(),
        artworkUrl: artwork,
      );
    } catch (_) {
      return null;
    }
  }

  Future<NowPlaying?> _somaFm(Uri stream) async {
    if (!stream.host.contains('somafm.com')) return null;
    final segment = stream.pathSegments.isEmpty ? '' : stream.pathSegments.first;
    if (segment.isEmpty) return null;
    final channel = segment.split('-').first;
    if (channel.isEmpty) return null;
    try {
      final uri = Uri.parse('https://somafm.com/songs/$channel.json');
      final response = await _get(uri);
      if (response == null) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final songs = decoded['songs'];
      if (songs is! List || songs.isEmpty || songs.first is! Map) return null;
      final song = Map<String, dynamic>.from(songs.first as Map);
      final artist = (song['artist'] as String?)?.trim();
      final title = (song['title'] as String?)?.trim();
      if (title == null || title.isEmpty) return null;
      final art = (song['albumArt'] as String?)?.trim();
      final raw = [
        if (artist != null && artist.isNotEmpty) artist,
        title,
      ].join(' — ');
      return NowPlaying(
        raw: raw,
        artist: artist,
        title: title,
        album: (song['album'] as String?)?.trim(),
        artworkUrl: (art != null && art.startsWith('http')) ? art : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<NowPlaying?> _icecastStatus(Uri stream, {String? stationName}) async {
    final origin = stream.hasPort
        ? '${stream.scheme}://${stream.host}:${stream.port}'
        : '${stream.scheme}://${stream.host}';
    try {
      final response = await _get(Uri.parse('$origin/status-json.xsl'));
      if (response == null) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final stats = decoded['icestats'];
      if (stats is! Map) return null;
      final rawSource = stats['source'];
      final sources = <Map<String, dynamic>>[];
      if (rawSource is Map) {
        sources.add(Map<String, dynamic>.from(rawSource));
      } else if (rawSource is List) {
        for (final item in rawSource) {
          if (item is Map) sources.add(Map<String, dynamic>.from(item));
        }
      }
      if (sources.isEmpty) return null;

      final mount = stream.path;
      Map<String, dynamic>? matched;
      for (final source in sources) {
        final listen = '${source['listenurl'] ?? ''}';
        if (mount.isNotEmpty && listen.contains(mount)) {
          matched = source;
          break;
        }
      }
      matched ??= sources.length == 1 ? sources.first : null;
      if (matched == null) return null;
      final title = (matched['title'] as String?) ??
          (matched['yp_currently_playing'] as String?);
      if (title == null) return null;
      return NowPlayingParser.parse(title, stationName: stationName);
    } catch (_) {
      return null;
    }
  }

  Future<NowPlaying?> _icySidecar(Uri stream, {String? stationName}) async {
    final request = http.Request('GET', stream);
    request.headers['Icy-MetaData'] = '1';
    request.headers['User-Agent'] = _userAgent;
    request.headers['Accept'] = '*/*';

    final client = http.Client();
    try {
      final response = await client.send(request).timeout(_timeout);
      final metaint = int.tryParse(response.headers['icy-metaint'] ?? '');
      if (metaint == null || metaint <= 0 || metaint > 256000) return null;

      final needed = metaint * 4 + 1 + 255 * 16;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(_timeout)) {
        builder.add(chunk);
        if (builder.length >= needed) break;
      }
      final bytes = builder.takeBytes();
      var offset = 0;
      for (var i = 0; i < 4; i++) {
        final metaAt = offset + metaint;
        if (bytes.length <= metaAt) break;
        final metaLen = bytes[metaAt] * 16;
        offset = metaAt + 1;
        if (metaLen == 0) continue;
        if (bytes.length < offset + metaLen) break;
        final block = utf8.decode(
          bytes.sublist(offset, offset + metaLen),
          allowMalformed: true,
        );
        final parsed = NowPlayingParser.parse(block, stationName: stationName);
        if (parsed != null) return parsed;
        offset += metaLen;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<String?> _itunesArtwork(String query) async {
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': query,
        'media': 'music',
        'entity': 'song',
        'limit': '1',
      });
      final response = await _get(uri);
      if (response == null) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final results = decoded['results'];
      if (results is! List || results.isEmpty || results.first is! Map) {
        return null;
      }
      final raw = (results.first as Map)['artworkUrl100'] as String?;
      if (raw == null || raw.isEmpty) return null;
      return raw.replaceFirst('100x100bb', '300x300bb');
    } catch (_) {
      return null;
    }
  }

  Future<http.Response?> _get(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return response;
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeHls(Uri uri) {
    final path = uri.path.toLowerCase();
    return path.endsWith('.m3u8') || path.endsWith('.m3u');
  }
}

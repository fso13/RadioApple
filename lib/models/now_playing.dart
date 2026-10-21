class NowPlaying {
  const NowPlaying({
    required this.raw,
    this.artist,
    this.title,
    this.album,
    this.artworkUrl,
  });

  final String raw;
  final String? artist;
  final String? title;
  final String? album;
  final String? artworkUrl;

  bool get hasArtwork => artworkUrl != null && artworkUrl!.trim().isNotEmpty;

  String get displayTitle {
    final song = title?.trim();
    if (song != null && song.isNotEmpty) return song;
    return raw;
  }

  String? get displayArtist {
    final value = artist?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String get trayLine {
    final who = displayArtist;
    if (who != null) return '$who — $displayTitle';
    return displayTitle;
  }

  NowPlaying copyWith({
    String? raw,
    String? artist,
    String? title,
    String? album,
    String? artworkUrl,
    bool clearArtwork = false,
  }) {
    return NowPlaying(
      raw: raw ?? this.raw,
      artist: artist ?? this.artist,
      title: title ?? this.title,
      album: album ?? this.album,
      artworkUrl: clearArtwork ? null : (artworkUrl ?? this.artworkUrl),
    );
  }
}

abstract final class NowPlayingParser {
  static final _streamTitle = RegExp(
    r"StreamTitle='(.*?)';",
    caseSensitive: false,
    dotAll: true,
  );
  static final _dashSplit = RegExp(r'\s+[-–—]\s+');
  static const _junk = {
    '-',
    '—',
    '–',
    'n/a',
    'na',
    'null',
    'unknown',
    'undefined',
    'advert',
    'advertisement',
    'реклама',
  };

  static String? unwrapIcyBlock(String raw) {
    final match = _streamTitle.firstMatch(raw);
    if (match != null) return match.group(1)?.trim();
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  static NowPlaying? parse(String raw, {String? stationName}) {
    final unwrapped = unwrapIcyBlock(raw);
    if (unwrapped == null) return null;
    final cleaned = unwrapped.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty || cleaned.length > 240) return null;
    if (_junk.contains(cleaned.toLowerCase())) return null;
    if (stationName != null &&
        stationName.trim().isNotEmpty &&
        cleaned.toLowerCase() == stationName.trim().toLowerCase()) {
      return null;
    }
    if (cleaned.startsWith('http://') || cleaned.startsWith('https://')) {
      return null;
    }

    final parts = cleaned.split(_dashSplit);
    if (parts.length >= 2) {
      final artist = parts.first.trim();
      final title = parts.sublist(1).join(' — ').trim();
      if (artist.isEmpty || title.isEmpty) {
        return NowPlaying(raw: cleaned, title: cleaned);
      }
      return NowPlaying(raw: cleaned, artist: artist, title: title);
    }
    return NowPlaying(raw: cleaned, title: cleaned);
  }

  static bool looksLikeImageUrl(String? url) {
    if (url == null) return false;
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.webp') ||
        path.endsWith('.gif');
  }
}

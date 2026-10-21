import 'package:flutter/material.dart';
import 'package:radio_mac/theme/app_palette.dart';

class RadioStation {
  const RadioStation({
    required this.id,
    required this.name,
    required this.url,
    required this.genre,
    this.comment,
    this.logoUrl,
    this.isFavorite = false,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final String url;
  final String genre;
  final String? comment;
  final String? logoUrl;
  final bool isFavorite;
  final bool builtIn;

  bool get hasComment => comment != null && comment!.trim().isNotEmpty;
  bool get hasLogo => logoUrl != null && logoUrl!.trim().isNotEmpty;

  RadioStation copyWith({
    String? id,
    String? name,
    String? url,
    String? genre,
    String? comment,
    String? logoUrl,
    bool? isFavorite,
    bool? builtIn,
    bool clearComment = false,
    bool clearLogo = false,
  }) {
    return RadioStation(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      genre: genre ?? this.genre,
      comment: clearComment ? null : (comment ?? this.comment),
      logoUrl: clearLogo ? null : (logoUrl ?? this.logoUrl),
      isFavorite: isFavorite ?? this.isFavorite,
      builtIn: builtIn ?? this.builtIn,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'genre': genre,
        'comment': comment,
        'logoUrl': logoUrl,
        'isFavorite': isFavorite,
        'builtIn': builtIn,
      };

  factory RadioStation.fromJson(Map<String, dynamic> json) {
    return RadioStation(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      genre: json['genre'] as String? ?? GenreCatalog.other,
      comment: json['comment'] as String?,
      logoUrl: json['logoUrl'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      builtIn: json['builtIn'] as bool? ?? false,
    );
  }
}

abstract final class GenreCatalog {
  static const jazz = 'Jazz';
  static const electronic = 'Electronic';
  static const rock = 'Rock';
  static const classical = 'Classical';
  static const news = 'News';
  static const ambient = 'Ambient';
  static const pop = 'Pop';
  static const chill = 'Chill';
  static const folk = 'Folk';
  static const world = 'World';
  static const shanson = 'Shanson';
  static const retro = 'Retro';
  static const other = 'Other';

  static const presets = <String>[
    jazz,
    electronic,
    rock,
    classical,
    news,
    ambient,
    pop,
    chill,
    folk,
    world,
    shanson,
    retro,
    other,
  ];

  static String normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return other;
    for (final preset in presets) {
      if (preset.toLowerCase() == trimmed.toLowerCase()) return preset;
    }
    return trimmed;
  }

  static Color colorFor(String genre, AppPalette palette) {
    switch (genre.toLowerCase()) {
      case 'jazz':
        return palette.orange;
      case 'electronic':
        return palette.accent;
      case 'rock':
        return palette.red;
      case 'classical':
        return palette.cyan;
      case 'news':
        return palette.yellow;
      case 'ambient':
        return palette.green;
      case 'pop':
        return palette.accentPink;
      case 'chill':
        return palette.cyan;
      case 'folk':
        return palette.orange;
      case 'world':
        return palette.green;
      case 'shanson':
        return palette.orange;
      case 'retro':
        return palette.yellow;
      default:
        return palette.mutedBright;
    }
  }
}

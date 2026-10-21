import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radio_mac/models/equalizer_preset.dart';
import 'package:radio_mac/models/now_playing.dart';
import 'package:radio_mac/models/radio_station.dart';
import 'package:radio_mac/services/logo_resolver.dart';
import 'package:radio_mac/theme/app_palette.dart';

void main() {
  test('genre catalog normalizes empty and known names', () {
    expect(GenreCatalog.normalize(''), GenreCatalog.other);
    expect(GenreCatalog.normalize('jazz'), GenreCatalog.jazz);
    expect(GenreCatalog.normalize('Synthwave'), 'Synthwave');
    expect(GenreCatalog.normalize('shanson'), GenreCatalog.shanson);
  });

  test('station reports logo when url is set', () {
    const withLogo = RadioStation(
      id: 'a',
      name: 'Test',
      url: 'https://example.com/stream',
      genre: GenreCatalog.rock,
      logoUrl: 'https://example.com/logo.png',
    );
    const withoutLogo = RadioStation(
      id: 'b',
      name: 'Test',
      url: 'https://example.com/stream',
      genre: GenreCatalog.rock,
    );
    expect(withLogo.hasLogo, isTrue);
    expect(withoutLogo.hasLogo, isFalse);
  });

  test('logo resolver keeps brand host and drops CDNs', () {
    expect(LogoResolver.hostOf('https://ice1.somafm.com/groovesalad'),
        'ice1.somafm.com');
    expect(LogoResolver.brandHost('ice1.somafm.com'), 'somafm.com');
    expect(LogoResolver.brandHost('hostingradio.ru'), isNull);
    expect(LogoResolver.brandHost('stream.hostingradio.ru'), isNull);
    expect(LogoResolver.hostOf('not a url'), isNull);
  });

  test('now playing parser splits artist and title', () {
    final split = NowPlayingParser.parse('Queen - Bohemian Rhapsody')!;
    expect(split.artist, 'Queen');
    expect(split.title, 'Bohemian Rhapsody');
    expect(split.trayLine, 'Queen — Bohemian Rhapsody');

    final icy = NowPlayingParser.parse(
      "StreamTitle='Кино — Группа крови';StreamUrl='';",
    )!;
    expect(icy.artist, 'Кино');
    expect(icy.title, 'Группа крови');

    expect(NowPlayingParser.parse(' - '), isNull);
    expect(
      NowPlayingParser.parse('Русское Радио', stationName: 'Русское Радио'),
      isNull,
    );
    expect(NowPlayingParser.parse('https://example.com/x'), isNull);

    final onlyTitle = NowPlayingParser.parse('Airwaves')!;
    expect(onlyTitle.artist, isNull);
    expect(onlyTitle.displayTitle, 'Airwaves');
  });

  test('equalizer catalog keeps ten bands and clamps gains', () {
    expect(EqualizerCatalog.presets.first.id, EqualizerCatalog.flatId);
    for (final preset in EqualizerCatalog.presets) {
      expect(preset.gains, hasLength(EqualizerCatalog.bandCount));
    }
    expect(
      EqualizerCatalog.clampGains([40, -40]),
      [12, -12, 0, 0, 0, 0, 0, 0, 0, 0],
    );
    expect(EqualizerCatalog.labelForHz(1000), '1k');
    expect(EqualizerCatalog.labelForHz(125), '125');
  });

  test('dark palette uses dracula ink', () {
    expect(AppPalette.dark.ink, const Color(0xFFF8F8F2));
  });
}

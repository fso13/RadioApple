import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:radio_mac/models/now_playing.dart';
import 'package:radio_mac/models/radio_station.dart';
import 'package:radio_mac/services/app_settings.dart';
import 'package:radio_mac/services/equalizer_service.dart';
import 'package:radio_mac/services/native_radio_player.dart';
import 'package:radio_mac/services/now_playing_lookup.dart';
import 'package:radio_mac/services/station_library.dart';

final radioPlayer = RadioPlayerService();

enum RadioPlaybackStatus { idle, loading, playing, paused, error }

class RadioPlayerService extends ChangeNotifier {
  StreamSubscription<NativePlayerEvent>? _nativeSub;
  Timer? _nowPlayingTimer;

  RadioStation? _station;
  RadioPlaybackStatus _status = RadioPlaybackStatus.idle;
  NowPlaying? _nowPlaying;
  String? _errorMessage;
  double _volume = 0.8;
  bool _icyLive = false;
  int _nowPlayingGen = 0;

  RadioStation? get station => _station;
  RadioPlaybackStatus get status => _status;
  NowPlaying? get nowPlaying => _nowPlaying;
  String? get trackTitle => _nowPlaying?.trayLine;
  String? get errorMessage => _errorMessage;
  double get volume => _volume;
  bool get isPlaying => _status == RadioPlaybackStatus.playing;
  bool get isActive =>
      _status == RadioPlaybackStatus.playing ||
      _status == RadioPlaybackStatus.paused ||
      _status == RadioPlaybackStatus.loading;

  Future<void> initialize() async {
    _volume = appSettings.volume;

    await NativeRadioPlayer.instance.startListening();
    _nativeSub = NativeRadioPlayer.instance.events.listen(_onNativeEvent);

    await equalizerService.load();
    equalizerService.addListener(_onEqualizerChanged);

    try {
      await NativeRadioPlayer.instance.setVolume(_volume);
    } catch (_) {}

    stationLibrary.addListener(_syncStationFromLibrary);

    if (appSettings.resumeLastStation && appSettings.lastStationId != null) {
      final station = stationLibrary.byId(appSettings.lastStationId!);
      if (station != null) {
        await play(station);
      }
    }
  }

  void _onEqualizerChanged() {
    if (_station == null || !isActive) return;
    unawaited(play(_station!));
  }

  void _onNativeEvent(NativePlayerEvent event) {
    switch (event.type) {
      case 'state':
        final next = switch (event.value) {
          'playing' => RadioPlaybackStatus.playing,
          'paused' => RadioPlaybackStatus.paused,
          'loading' => RadioPlaybackStatus.loading,
          'error' => RadioPlaybackStatus.error,
          _ => RadioPlaybackStatus.idle,
        };
        if (next == RadioPlaybackStatus.idle &&
            _status == RadioPlaybackStatus.error) {
          return;
        }
        if (next == RadioPlaybackStatus.error) {
          _errorMessage ??= 'Не удалось открыть поток';
        }
        if (next != _status) {
          _status = next;
          notifyListeners();
        }
        break;
      case 'icy':
        final title = event.value?.trim();
        if (title != null && title.isNotEmpty) {
          _applyNowPlaying(
            NowPlayingParser.parse(title, stationName: _station?.name),
            fromIcy: true,
          );
        }
        break;
      case 'icy_url':
        final url = event.value?.trim();
        if (url != null && url.isNotEmpty) {
          _handleIcyUrl(url);
        }
        break;
      case 'error':
        _status = RadioPlaybackStatus.error;
        _errorMessage = event.message ?? 'Не удалось открыть поток';
        _stopNowPlayingPoll();
        notifyListeners();
        break;
    }
  }

  void _handleIcyUrl(String url) {
    if (NowPlayingParser.looksLikeImageUrl(url) && _nowPlaying != null) {
      _applyNowPlaying(_nowPlaying, artworkUrl: url);
    } else if (_station != null) {
      unawaited(stationLibrary.resolveFromHomepage(_station!.id, url));
    }
  }

  void _syncStationFromLibrary() {
    final current = _station;
    if (current == null) return;
    final fresh = stationLibrary.byId(current.id);
    if (fresh == null || fresh.logoUrl == current.logoUrl) return;
    _station = current.copyWith(logoUrl: fresh.logoUrl);
    notifyListeners();
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    _syncMacNowPlaying();
  }

  void _syncMacNowPlaying() {
    if (defaultTargetPlatform != TargetPlatform.macOS) return;

    if (_station == null || _status == RadioPlaybackStatus.idle) {
      unawaited(NativeRadioPlayer.instance.clearNowPlaying());
      return;
    }

    final station = _station!;
    final np = _nowPlaying;
    final trackTitle = np?.displayTitle.trim();
    final hasDistinctTrack = trackTitle != null &&
        trackTitle.isNotEmpty &&
        trackTitle.toLowerCase() != station.name.trim().toLowerCase();

    final title = hasDistinctTrack ? trackTitle! : station.name;
    final artist = hasDistinctTrack
        ? (np?.displayArtist?.trim().isNotEmpty == true
            ? np!.displayArtist!.trim()
            : station.name)
        : 'RadioMac';

    final artworkUrl = (np?.hasArtwork == true ? np!.artworkUrl : null) ??
        station.logoUrl;

    final isPlaying = _status == RadioPlaybackStatus.playing;

    unawaited(
      NativeRadioPlayer.instance.updateNowPlaying(
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
        isPlaying: isPlaying,
        isLive: true,
      ),
    );
  }

  Future<void> play(RadioStation station) async {
    _station = station;
    _nowPlaying = null;
    _icyLive = false;
    _nowPlayingGen++;
    _errorMessage = null;
    _status = RadioPlaybackStatus.loading;
    notifyListeners();
    await appSettings.setLastStationId(station.id);
    _restartNowPlayingPoll();

    try {
      await NativeRadioPlayer.instance.play(station.url);
      await NativeRadioPlayer.instance.setVolume(_volume);
      await _syncNativeState();
    } catch (_) {
      _status = RadioPlaybackStatus.error;
      _errorMessage = 'Не удалось открыть поток';
      _stopNowPlayingPoll();
      notifyListeners();
    }
  }

  Future<void> _syncNativeState() async {
    final value = await NativeRadioPlayer.instance.currentState();
    if (value == null) return;
    final next = switch (value) {
      'playing' => RadioPlaybackStatus.playing,
      'paused' => RadioPlaybackStatus.paused,
      'loading' => RadioPlaybackStatus.loading,
      'error' => RadioPlaybackStatus.error,
      _ => RadioPlaybackStatus.idle,
    };
    if (next != _status) {
      _status = next;
      notifyListeners();
    }
  }

  String? consumeError() {
    final message = _errorMessage;
    _errorMessage = null;
    return message;
  }

  Future<void> togglePlayPause() async {
    if (_status == RadioPlaybackStatus.playing) {
      await NativeRadioPlayer.instance.pause();
      return;
    }
    if (_status == RadioPlaybackStatus.paused && _station != null) {
      await NativeRadioPlayer.instance.resume();
      return;
    }
    if (_station != null) {
      await play(_station!);
    }
  }

  Future<void> stop() async {
    _stopNowPlayingPoll();
    _nowPlayingGen++;
    try {
      await NativeRadioPlayer.instance.stop();
    } catch (_) {}
    _status = RadioPlaybackStatus.idle;
    _nowPlaying = null;
    _icyLive = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    try {
      await NativeRadioPlayer.instance.setVolume(_volume);
    } catch (_) {}
    await appSettings.setVolume(_volume);
    notifyListeners();
  }

  void _restartNowPlayingPoll() {
    _stopNowPlayingPoll();
    unawaited(_pollNowPlaying());
    _nowPlayingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_pollNowPlaying());
    });
  }

  void _stopNowPlayingPoll() {
    _nowPlayingTimer?.cancel();
    _nowPlayingTimer = null;
  }

  Future<void> _pollNowPlaying() async {
    final station = _station;
    final gen = _nowPlayingGen;
    if (station == null) return;
    if (_status != RadioPlaybackStatus.playing &&
        _status != RadioPlaybackStatus.loading) {
      return;
    }
    final track = await NowPlayingLookup.instance.resolve(
      streamUrl: station.url,
      stationName: station.name,
      allowIcySidecar: !_icyLive,
    );
    if (gen != _nowPlayingGen) return;
    _applyNowPlaying(track);
  }

  void _applyNowPlaying(
    NowPlaying? track, {
    bool fromIcy = false,
    String? artworkUrl,
  }) {
    if (track == null) return;
    if (fromIcy) _icyLive = true;

    final art = artworkUrl ?? track.artworkUrl;
    if (_nowPlaying?.raw == track.raw) {
      if (art != null && !_nowPlaying!.hasArtwork) {
        _nowPlaying = _nowPlaying!.copyWith(artworkUrl: art);
        notifyListeners();
      }
      return;
    }

    _nowPlaying = track.copyWith(artworkUrl: art);
    notifyListeners();
    unawaited(_fillArtwork());
  }

  Future<void> _fillArtwork() async {
    final gen = _nowPlayingGen;
    final current = _nowPlaying;
    if (current == null || current.hasArtwork) return;
    if (_station?.genre == GenreCatalog.news) return;
    final art = await NowPlayingLookup.instance.artworkFor(current);
    if (gen != _nowPlayingGen) return;
    if (_nowPlaying?.raw != current.raw) return;
    if (art == null) return;
    _nowPlaying = _nowPlaying!.copyWith(artworkUrl: art);
    notifyListeners();
  }

  @override
  void dispose() {
    _stopNowPlayingPoll();
    equalizerService.removeListener(_onEqualizerChanged);
    stationLibrary.removeListener(_syncStationFromLibrary);
    _nativeSub?.cancel();
    unawaited(NativeRadioPlayer.instance.dispose());
    super.dispose();
  }
}

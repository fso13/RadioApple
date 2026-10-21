import 'dart:async';

import 'package:flutter/services.dart';

class NativePlayerEvent {
  const NativePlayerEvent({required this.type, this.value, this.message});

  final String type;
  final String? value;
  final String? message;
}

class NativeRadioPlayer {
  NativeRadioPlayer._();

  static final instance = NativeRadioPlayer._();

  static const _methods = MethodChannel('radio_mac/player');
  static const _events = EventChannel('radio_mac/player_events');

  StreamSubscription<dynamic>? _sub;
  final _controller = StreamController<NativePlayerEvent>.broadcast();

  Stream<NativePlayerEvent> get events => _controller.stream;

  Future<void> startListening() async {
    if (_sub != null) return;
    _sub = _events.receiveBroadcastStream().listen((raw) {
      if (raw is! Map) return;
      _controller.add(
        NativePlayerEvent(
          type: raw['type'] as String? ?? '',
          value: (raw['value'] ?? raw['title'] ?? raw['url']) as String?,
          message: raw['message'] as String?,
        ),
      );
    });
  }

  Future<void> play(String url) => _methods.invokeMethod<void>('play', url);

  Future<void> pause() => _methods.invokeMethod<void>('pause');

  Future<void> resume() => _methods.invokeMethod<void>('resume');

  Future<void> stop() => _methods.invokeMethod<void>('stop');

  Future<void> setVolume(double value) =>
      _methods.invokeMethod<void>('setVolume', value);

  Future<void> setEqEnabled(bool enabled) =>
      _methods.invokeMethod<void>('setEqEnabled', enabled);

  Future<void> setEqGains(List<double> gains) =>
      _methods.invokeMethod<void>('setEqGains', gains);

  Future<String?> currentState() async {
    final value = await _methods.invokeMethod<String>('getState');
    return value;
  }

  Future<void> updateNowPlaying({
    required String title,
    String? artist,
    String? artworkUrl,
    required bool isPlaying,
    bool isLive = true,
  }) =>
      _methods.invokeMethod<void>('updateNowPlaying', {
        'title': title,
        'artist': artist,
        'artworkUrl': artworkUrl,
        'isPlaying': isPlaying,
        'isLive': isLive,
      });

  Future<void> clearNowPlaying() => _methods.invokeMethod<void>('clearNowPlaying');

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}

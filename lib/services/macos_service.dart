import 'package:flutter/services.dart';

class LaunchAtLoginResult {
  const LaunchAtLoginResult({
    required this.ok,
    this.enabled,
    this.supported,
    this.error,
  });

  final bool ok;
  final bool? enabled;
  final bool? supported;
  final String? error;
}

class MacOSService {
  static const _channel = MethodChannel('radio_mac/macos');

  static Future<void> activate() async {
    try {
      await _channel.invokeMethod<void>('activate');
    } catch (_) {}
  }

  static Future<LaunchAtLoginResult> getLaunchAtLogin() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('getLaunchAtLogin');
      return _parse(raw);
    } catch (e) {
      return LaunchAtLoginResult(ok: false, error: e.toString());
    }
  }

  static Future<LaunchAtLoginResult> setLaunchAtLogin(bool enabled) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'setLaunchAtLogin',
        enabled,
      );
      return _parse(raw);
    } catch (e) {
      return LaunchAtLoginResult(ok: false, error: e.toString());
    }
  }

  static LaunchAtLoginResult _parse(dynamic raw) {
    if (raw is Map) {
      return LaunchAtLoginResult(
        ok: raw['ok'] == true,
        enabled: raw['enabled'] as bool?,
        supported: raw['supported'] as bool?,
        error: raw['error'] as String?,
      );
    }
    return const LaunchAtLoginResult(ok: false, error: 'Unexpected response');
  }
}

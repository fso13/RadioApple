import 'dart:async';

import 'package:radio_mac/utils/app_exit.dart';
import 'package:system_tray/system_tray.dart';

class SystemTrayService {
  final SystemTray _systemTray = SystemTray();
  final Menu _menu = Menu();

  final StreamController<void> _showWindowController =
      StreamController.broadcast();
  final StreamController<void> _openSettingsController =
      StreamController.broadcast();
  final StreamController<void> _toggleWindowController =
      StreamController.broadcast();
  final StreamController<void> _playPauseController =
      StreamController.broadcast();
  final StreamController<void> _stopController = StreamController.broadcast();

  Stream<void> get onShowWindow => _showWindowController.stream;
  Stream<void> get onOpenSettings => _openSettingsController.stream;
  Stream<void> get onToggleWindow => _toggleWindowController.stream;
  Stream<void> get onPlayPause => _playPauseController.stream;
  Stream<void> get onStop => _stopController.stream;

  bool _playing = false;
  String? _stationName;
  String? _trackLabel;

  Future<void> initialize() async {
    await _systemTray.initSystemTray(
      iconPath: 'assets/AppIcons/tray_icon.png',
      toolTip: 'RadioMac',
    );
    await _rebuildMenu();
    await _systemTray.setContextMenu(_menu);

    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        _toggleWindowController.add(null);
      } else if (eventName == kSystemTrayEventRightClick) {
        _systemTray.popUpContextMenu();
      }
    });
  }

  Future<void> refresh({
    required bool playing,
    String? stationName,
    String? trackLabel,
  }) async {
    _playing = playing;
    _stationName = stationName;
    _trackLabel = trackLabel;
    await _rebuildMenu();
    await _systemTray.setContextMenu(_menu);
    final parts = <String>[
      if (stationName != null && stationName.isNotEmpty) stationName,
      if (trackLabel != null && trackLabel.isNotEmpty) trackLabel,
    ];
    final body = parts.join(' · ');
    final tip = body.isEmpty
        ? 'RadioMac'
        : (playing ? '▶ $body' : body);
    await _systemTray.setToolTip(tip.length > 90 ? '${tip.substring(0, 89)}…' : tip);
  }

  Future<void> _rebuildMenu() async {
    final nowPlaying = _stationName;
    final track = _trackLabel;
    await _menu.buildFrom([
      if (nowPlaying != null && nowPlaying.isNotEmpty)
        MenuItemLabel(
          label: nowPlaying,
          enabled: false,
        ),
      if (track != null && track.isNotEmpty)
        MenuItemLabel(
          label: track.length > 48 ? '${track.substring(0, 47)}…' : track,
          enabled: false,
        ),
      if ((nowPlaying != null && nowPlaying.isNotEmpty) ||
          (track != null && track.isNotEmpty))
        MenuSeparator(),
      MenuItemLabel(
        label: _playing ? 'Пауза' : 'Играть',
        onClicked: (_) => _playPauseController.add(null),
      ),
      MenuItemLabel(
        label: 'Стоп',
        onClicked: (_) => _stopController.add(null),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Показать',
        onClicked: (_) => _showWindowController.add(null),
      ),
      MenuItemLabel(
        label: 'Настройки',
        onClicked: (_) => _openSettingsController.add(null),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Завершить',
        onClicked: (_) async {
          await quitAppCompletely();
        },
      ),
    ]);
  }

  void dispose() {
    _showWindowController.close();
    _openSettingsController.close();
    _toggleWindowController.close();
    _playPauseController.close();
    _stopController.close();
  }
}

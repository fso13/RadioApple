import 'package:flutter/material.dart';
import 'package:radio_mac/services/app_settings.dart';
import 'package:radio_mac/services/equalizer_service.dart';
import 'package:radio_mac/services/macos_service.dart';
import 'package:radio_mac/services/radio_player_service.dart';
import 'package:radio_mac/services/station_library.dart';
import 'package:radio_mac/services/system_tray_service.dart';
import 'package:radio_mac/services/theme_service.dart';
import 'package:radio_mac/theme/app_theme.dart';
import 'package:radio_mac/views/main_window.dart';
import 'package:radio_mac/views/settings_window.dart';
import 'package:window_manager/window_manager.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  await themeService.load();
  await appSettings.load();
  await stationLibrary.load();

  const windowOptions = WindowOptions(
    size: Size(420, 680),
    center: true,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.hide();
  });

  runApp(const RadioMacApp());
}

class RadioMacApp extends StatefulWidget {
  const RadioMacApp({super.key});

  @override
  State<RadioMacApp> createState() => _RadioMacAppState();
}

class _RadioMacAppState extends State<RadioMacApp> {
  final SystemTrayService _systemTrayService = SystemTrayService();

  bool _showWindow = false;
  bool _mountWindow = false;
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    themeService.addListener(_onChanged);
    equalizerService.addListener(_onChanged);
    radioPlayer.addListener(_onPlayerChanged);
    _initializeServices();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _onPlayerChanged() async {
    if (mounted) setState(() {});
    await _systemTrayService.refresh(
      playing: radioPlayer.isPlaying,
      stationName: radioPlayer.station?.name,
      trackLabel: radioPlayer.nowPlaying?.trayLine,
    );
  }

  Future<void> _initializeServices() async {
    await _systemTrayService.initialize();
    await radioPlayer.initialize();

    _systemTrayService.onToggleWindow.listen((_) => _toggleWindow());
    _systemTrayService.onShowWindow.listen((_) => _showMainWindow());
    _systemTrayService.onOpenSettings.listen((_) => _openSettings());
    _systemTrayService.onPlayPause.listen((_) {
      if (radioPlayer.station == null && stationLibrary.stations.isNotEmpty) {
        radioPlayer.play(stationLibrary.stations.first);
        return;
      }
      radioPlayer.togglePlayPause();
    });
    _systemTrayService.onStop.listen((_) => radioPlayer.stop());
  }

  Future<void> _toggleWindow() async {
    if (!_showWindow) {
      await _showMainWindow();
      return;
    }
    setState(() {
      _showWindow = false;
      _showSettings = false;
    });
    await windowManager.hide();
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted || _showWindow) return;
    setState(() => _mountWindow = false);
  }

  Future<void> _showMainWindow() async {
    setState(() {
      _showWindow = true;
      _mountWindow = true;
      _showSettings = false;
    });
    await MacOSService.activate();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _openSettings() async {
    setState(() {
      _showSettings = true;
      _showWindow = true;
      _mountWindow = true;
    });
    await MacOSService.activate();
    await windowManager.show();
    await windowManager.focus();
  }

  void _closeSettings() {
    setState(() => _showSettings = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeService.themeMode,
      home: _mountWindow
          ? (_showSettings
              ? SettingsWindow(onClose: _closeSettings)
              : MainWindow(
                  onClose: _toggleWindow,
                  onOpenSettings: _openSettings,
                ))
          : const SizedBox.shrink(),
    );
  }

  @override
  void dispose() {
    themeService.removeListener(_onChanged);
    equalizerService.removeListener(_onChanged);
    radioPlayer.removeListener(_onPlayerChanged);
    _systemTrayService.dispose();
    radioPlayer.dispose();
    super.dispose();
  }
}

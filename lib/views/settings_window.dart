import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:radio_mac/data/help_guide.dart';
import 'package:radio_mac/services/app_settings.dart';
import 'package:radio_mac/services/equalizer_service.dart';
import 'package:radio_mac/widgets/equalizer_sheet.dart';
import 'package:radio_mac/services/macos_service.dart';
import 'package:radio_mac/services/station_library.dart';
import 'package:radio_mac/services/theme_service.dart';
import 'package:radio_mac/theme/app_palette.dart';
import 'package:radio_mac/utils/app_exit.dart';
import 'package:radio_mac/widgets/app_panel.dart';
import 'package:radio_mac/widgets/brand_mark.dart';

class SettingsWindow extends StatefulWidget {
  const SettingsWindow({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  bool _launchAtStartup = false;
  bool _launchAtLoginSupported = true;
  bool _resumeLast = false;
  bool _showHelp = false;
  String? _expandedHelpId;
  String _appVersion = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _resumeLast = appSettings.resumeLastStation;
    _loadSettings();
    _loadAppVersion();
    themeService.addListener(_onChanged);
    appSettings.addListener(_onChanged);
    equalizerService.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeService.removeListener(_onChanged);
    appSettings.removeListener(_onChanged);
    equalizerService.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final launch = await MacOSService.getLaunchAtLogin();
    if (!mounted) return;
    setState(() {
      _launchAtLoginSupported = launch.supported ?? true;
      _launchAtStartup = launch.enabled ?? appSettings.autoStartEnabled;
      _resumeLast = appSettings.resumeLastStation;
    });
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _appVersion = info.version;
      _buildNumber = info.buildNumber;
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _setAutoStartEnabled(bool enabled) async {
    final result = await MacOSService.setLaunchAtLogin(enabled);
    if (!result.ok) {
      _showSnack(result.error ?? 'Не удалось изменить автозапуск');
      final current = await MacOSService.getLaunchAtLogin();
      if (!mounted) return;
      setState(() {
        _launchAtStartup = current.enabled ?? false;
        _launchAtLoginSupported = current.supported ?? false;
      });
      return;
    }
    await appSettings.setAutoStartEnabled(result.enabled ?? enabled);
    if (!mounted) return;
    setState(() {
      _launchAtStartup = result.enabled ?? enabled;
      _launchAtLoginSupported = result.supported ?? true;
    });
  }

  Future<void> _quitApp() async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Завершить работу'),
        content: const Text(
          'Приложение будет закрыто полностью, включая иконку в меню-баре. '
          'Эфир остановится.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена', style: TextStyle(color: palette.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Завершить', style: TextStyle(color: palette.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await quitAppCompletely();
  }

  Future<void> _restoreStations() async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Восстановить каталог'),
        content: const Text(
          'Встроенные станции вернутся к исходным. Ваши добавленные станции '
          'останутся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена', style: TextStyle(color: palette.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Восстановить',
                style: TextStyle(color: palette.accent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await stationLibrary.restoreDefaults();
    _showSnack('Встроенные станции восстановлены');
  }

  IconData _helpIcon(String key) {
    switch (key) {
      case 'bolt':
        return Icons.bolt_outlined;
      case 'play':
        return Icons.play_circle_outline;
      case 'add':
        return Icons.add_circle_outline;
      case 'tag':
        return Icons.sell_outlined;
      case 'link':
        return Icons.link;
      case 'tune':
        return Icons.tune;
      default:
        return Icons.help_outline;
    }
  }

  Widget _buildHelpBody(AppPalette palette) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Как держать RadioMac в трее, добавлять потоки и группировать '
            'станции по жанрам.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: palette.muted,
            ),
          ),
        ),
        for (final topic in HelpGuide.topics) ...[
          Material(
            color: palette.bgElevated.withValues(alpha: 0.78),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: palette.accent.withValues(alpha: 0.18)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: PageStorageKey('help_${topic.id}'),
                initiallyExpanded: _expandedHelpId == topic.id,
                onExpansionChanged: (open) {
                  setState(() {
                    _expandedHelpId = open ? topic.id : null;
                  });
                },
                leading: Icon(
                  _helpIcon(topic.icon),
                  size: 20,
                  color: palette.accent,
                ),
                title: Text(
                  topic.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                children: [
                  for (var i = 0; i < topic.paragraphs.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        topic.paragraphs[i],
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: palette.ink.withValues(alpha: 0.92),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPanel(
        title: _showHelp ? 'help.md' : 'settings.cfg',
        actions: [
          if (_showHelp)
            IconButton(
              icon: Icon(Icons.arrow_back, size: 16, color: palette.muted),
              onPressed: () => setState(() {
                _showHelp = false;
                _expandedHelpId = null;
              }),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'К настройкам',
            ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: palette.muted),
            onPressed: widget.onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
        child: _showHelp
            ? _buildHelpBody(palette)
            : ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: BrandMark(
                      iconSize: 36,
                      fontSize: 18,
                      showSubtitle: 'Настройки',
                    ),
                  ),
                  SettingsCard(
                    title: 'Тема',
                    subtitle: 'Выберите тему приложения',
                    icon: Icons.brush_outlined,
                    child: Column(
                      children: [
                        ChoiceOption(
                          label: 'Как в системе',
                          description:
                              'Автоматически переключать тему в зависимости от настроек системы',
                          selected: themeService.preference ==
                              AppThemePreference.system,
                          onTap: () => themeService
                              .setPreference(AppThemePreference.system),
                        ),
                        const SizedBox(height: 8),
                        ChoiceOption(
                          label: 'Светлая',
                          description: 'Всегда использовать светлую тему',
                          selected: themeService.preference ==
                              AppThemePreference.light,
                          onTap: () => themeService
                              .setPreference(AppThemePreference.light),
                        ),
                        const SizedBox(height: 8),
                        ChoiceOption(
                          label: 'Тёмная',
                          description: 'Всегда использовать тёмную тему',
                          selected: themeService.preference ==
                              AppThemePreference.dark,
                          onTap: () => themeService
                              .setPreference(AppThemePreference.dark),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SettingsCard(
                    title: 'Воспроизведение',
                    subtitle: 'Поведение при запуске',
                    icon: Icons.graphic_eq,
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Продолжать последнюю станцию',
                            style: TextStyle(fontSize: 13, color: palette.ink),
                          ),
                          subtitle: Text(
                            'При старте сразу включить последний эфир',
                            style:
                                TextStyle(fontSize: 11, color: palette.muted),
                          ),
                          value: _resumeLast,
                          onChanged: (value) async {
                            await appSettings.setResumeLastStation(value);
                            setState(() => _resumeLast = value);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SettingsCard(
                    title: 'Эквалайзер',
                    subtitle: equalizerService.enabled
                        ? 'Включён · ${equalizerService.preset.label}'
                        : 'Выключен',
                    icon: Icons.graphic_eq,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Десять полос, готовые пресеты и своя кривая. '
                          'Настройка запоминается и применяется ко всем станциям.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: palette.muted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => showEqualizerSheet(context),
                          icon: const Icon(Icons.tune, size: 16),
                          label: const Text(
                            'Открыть эквалайзер',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SettingsCard(
                    title: 'Автозапуск',
                    subtitle: 'RadioMac как фоновый агент',
                    icon: Icons.power_outlined,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Запуск при входе в систему',
                        style: TextStyle(fontSize: 13, color: palette.ink),
                      ),
                      subtitle: Text(
                        _launchAtLoginSupported
                            ? 'Появится в трее без иконки в Dock'
                            : 'Требуется macOS 13 или новее',
                        style: TextStyle(fontSize: 11, color: palette.muted),
                      ),
                      value: _launchAtStartup,
                      onChanged:
                          _launchAtLoginSupported ? _setAutoStartEnabled : null,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SettingsCard(
                    title: 'Каталог',
                    subtitle: 'Встроенные станции',
                    icon: Icons.library_music_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Свои ссылки не удаляются. Восстановление вернёт '
                          'каталог radiopotok.ru, рок-станции и SomaFM / Paradise.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: palette.muted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _restoreStations,
                          child: const Text(
                            'Восстановить встроенные',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SettingsCard(
                    title: 'Документация',
                    subtitle: 'Трей, потоки, жанры и настройки',
                    icon: Icons.menu_book_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Краткая справка: как добавить станцию, чем прямой '
                          'поток отличается от сайта радиостанции, и почему '
                          'окно можно закрыть без остановки эфира.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: palette.muted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => setState(() {
                            _showHelp = true;
                            _expandedHelpId = 'basics';
                          }),
                          icon: const Icon(Icons.menu_book_outlined, size: 16),
                          label: const Text(
                            'Открыть документацию',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SettingsCard(
                    title: 'О приложении',
                    subtitle: 'Версия и сборка',
                    icon: Icons.info_outline,
                    footer: Center(
                      child: Text(
                        '© RadioMac · built with coffee & streams 📻',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Menlo',
                          color: palette.muted,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        InfoRow(
                          label: 'Версия',
                          value: _appVersion.isEmpty ? '…' : _appVersion,
                        ),
                        const SizedBox(height: 8),
                        InfoRow(
                          label: 'Номер сборки',
                          value: _buildNumber.isEmpty ? '…' : _buildNumber,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SettingsCard(
                    title: 'Приложение',
                    subtitle: 'Полностью закрыть RadioMac',
                    icon: Icons.power_settings_new,
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _quitApp,
                        icon: Icon(Icons.power_settings_new,
                            size: 16, color: palette.red),
                        label: Text(
                          'Завершить работу',
                          style: TextStyle(fontSize: 13, color: palette.red),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: palette.red.withValues(alpha: 0.45),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
      ),
    );
  }
}

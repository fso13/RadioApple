import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:radio_mac/models/radio_station.dart';
import 'package:radio_mac/services/radio_player_service.dart';
import 'package:radio_mac/services/station_library.dart';
import 'package:radio_mac/theme/app_palette.dart';
import 'package:radio_mac/services/equalizer_service.dart';
import 'package:radio_mac/widgets/app_panel.dart';
import 'package:radio_mac/widgets/brand_mark.dart';
import 'package:radio_mac/widgets/equalizer_sheet.dart';
import 'package:radio_mac/widgets/station_logo.dart';

class MainWindow extends StatefulWidget {
  const MainWindow({
    super.key,
    required this.onClose,
    required this.onOpenSettings,
  });

  final VoidCallback onClose;
  final VoidCallback onOpenSettings;

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _listFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  /// `null` = all, `fav` = favorites, otherwise genre name.
  String? _filter;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    stationLibrary.addListener(_onChanged);
    radioPlayer.addListener(_onChanged);
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    stationLibrary.removeListener(_onChanged);
    radioPlayer.removeListener(_onChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _listFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<RadioStation> get _visible {
    final query = _searchController.text.trim().toLowerCase();
    return stationLibrary.stations.where((station) {
      if (_filter == 'fav' && !station.isFavorite) return false;
      if (_filter != null &&
          _filter != 'fav' &&
          GenreCatalog.normalize(station.genre) != _filter) {
        return false;
      }
      if (query.isEmpty) return true;
      return station.name.toLowerCase().contains(query) ||
          station.genre.toLowerCase().contains(query) ||
          station.url.toLowerCase().contains(query) ||
          (station.comment?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  void _focusSearch() {
    _searchFocusNode.requestFocus();
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
  }

  void _moveSelection(int delta, int count) {
    if (count == 0) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, count - 1);
    });
  }

  Future<void> _playAt(int index) async {
    final items = _visible;
    if (index < 0 || index >= items.length) return;
    await radioPlayer.play(items[index]);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final items = _visible;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      if (_searchFocusNode.hasFocus) {
        _searchFocusNode.unfocus();
        _listFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      widget.onClose();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.space && !_searchFocusNode.hasFocus) {
      radioPlayer.togglePlayPause();
      return KeyEventResult.handled;
    }

    if (_searchFocusNode.hasFocus) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1, items.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1, items.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _playAt(_selectedIndex);
      return KeyEventResult.handled;
    }

    final digits = <LogicalKeyboardKey, int>{
      LogicalKeyboardKey.digit1: 0,
      LogicalKeyboardKey.digit2: 1,
      LogicalKeyboardKey.digit3: 2,
      LogicalKeyboardKey.digit4: 3,
      LogicalKeyboardKey.digit5: 4,
      LogicalKeyboardKey.digit6: 5,
      LogicalKeyboardKey.digit7: 6,
      LogicalKeyboardKey.digit8: 7,
      LogicalKeyboardKey.digit9: 8,
    };
    final quick = digits[key];
    if (quick != null && quick < items.length) {
      _playAt(quick);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _editStation([RadioStation? existing]) async {
    final result = await showDialog<_StationDraft>(
      context: context,
      builder: (context) => _StationEditorDialog(
        existing: existing,
        genres: {
          ...GenreCatalog.presets,
          ...stationLibrary.genres,
        }.toList(),
      ),
    );
    if (result == null || !mounted) return;

    if (existing == null) {
      await stationLibrary.add(
        name: result.name,
        url: result.url,
        genre: result.genre,
        comment: result.comment,
        logoUrl: result.logoUrl,
      );
      _showSnack('Станция добавлена');
    } else {
      await stationLibrary.update(
        existing.copyWith(
          name: result.name,
          url: result.url,
          genre: result.genre,
          comment: result.comment,
          logoUrl: result.logoUrl,
          clearComment: result.comment.trim().isEmpty,
          clearLogo: result.logoUrl.trim().isEmpty,
        ),
      );
      _showSnack('Станция сохранена');
    }
  }

  Future<void> _deleteStation(RadioStation station) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить станцию'),
        content: Text('Удалить «${station.name}»?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена', style: TextStyle(color: palette.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Удалить', style: TextStyle(color: palette.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (radioPlayer.station?.id == station.id) {
      await radioPlayer.stop();
    }
    await stationLibrary.remove(station.id);
    _showSnack('Станция удалена');
  }

  void _showStationMenu(RadioStation station) {
    final palette = context.palette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            color: palette.bgElevated,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.play_arrow_rounded,
                      size: 20, color: palette.green),
                  title: Text('Играть',
                      style: TextStyle(color: palette.ink, fontSize: 14)),
                  onTap: () {
                    Navigator.pop(context);
                    radioPlayer.play(station);
                  },
                ),
                ListTile(
                  leading: Icon(
                    station.isFavorite ? Icons.star : Icons.star_border,
                    size: 20,
                    color: station.isFavorite
                        ? palette.yellow
                        : palette.mutedBright,
                  ),
                  title: Text(
                    station.isFavorite
                        ? 'Убрать из избранного'
                        : 'В избранное',
                    style: TextStyle(color: palette.ink, fontSize: 14),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    stationLibrary.toggleFavorite(station.id);
                  },
                ),
                ListTile(
                  leading:
                      Icon(Icons.edit_outlined, size: 20, color: palette.cyan),
                  title: Text('Изменить',
                      style: TextStyle(color: palette.ink, fontSize: 14)),
                  onTap: () {
                    Navigator.pop(context);
                    _editStation(station);
                  },
                ),
                ListTile(
                  leading:
                      Icon(Icons.delete_outline, size: 20, color: palette.red),
                  title: Text('Удалить',
                      style: TextStyle(fontSize: 14, color: palette.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteStation(station);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final items = _visible;
    if (_selectedIndex >= items.length && items.isNotEmpty) {
      _selectedIndex = items.length - 1;
    }

    if (radioPlayer.status == RadioPlaybackStatus.error &&
        radioPlayer.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final message = radioPlayer.consumeError();
        if (message != null) _showSnack(message);
      });
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            () => _editStation(),
      },
      child: Focus(
        focusNode: _listFocusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: AppPanel(
            title: 'now.playing',
            actions: [
              _HeaderIconButton(
                icon: Icons.settings_outlined,
                onPressed: widget.onOpenSettings,
              ),
              const SizedBox(width: 2),
              _HeaderIconButton(
                icon: Icons.close,
                onPressed: widget.onClose,
              ),
            ],
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: BrandMark(iconSize: 26, fontSize: 17),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  child: _SearchField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: (_) => setState(() => _selectedIndex = 0),
                    onClear: () {
                      _searchController.clear();
                      setState(() => _selectedIndex = 0);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _FilterChip(
                        label: 'Все',
                        selected: _filter == null,
                        onTap: () => setState(() {
                          _filter = null;
                          _selectedIndex = 0;
                        }),
                      ),
                      _FilterChip(
                        label: 'Избранное',
                        icon: Icons.star_rounded,
                        selected: _filter == 'fav',
                        accentColor: palette.yellow,
                        onTap: () => setState(() {
                          _filter = 'fav';
                          _selectedIndex = 0;
                        }),
                      ),
                      for (final genre in stationLibrary.genres)
                        _FilterChip(
                          label: genre,
                          selected: _filter == genre,
                          accentColor: GenreCatalog.colorFor(genre, palette),
                          onTap: () => setState(() {
                            _filter = genre;
                            _selectedIndex = 0;
                          }),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _editStation(),
                      icon: Icon(Icons.add, size: 14, color: palette.accent),
                      label: Text(
                        'Добавить',
                        style: TextStyle(fontSize: 11, color: palette.accent),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? _EmptyState(
                          icon: _searchController.text.isNotEmpty
                              ? Icons.search_off
                              : Icons.radio_outlined,
                          title: _searchController.text.isNotEmpty
                              ? 'Ничего не найдено для «${_searchController.text}»'
                              : _filter == 'fav'
                                  ? 'В избранном пока пусто'
                                  : 'Добавьте первую станцию',
                          subtitle: _searchController.text.isEmpty
                              ? '⌘N — новая ссылка на поток'
                              : null,
                        )
                      : ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final station = items[index];
                            return _StationTile(
                              station: station,
                              index: index,
                              selected: index == _selectedIndex,
                              playing: radioPlayer.station?.id == station.id &&
                                  radioPlayer.isActive,
                              onTap: () => radioPlayer.play(station),
                              onShowMenu: () => _showStationMenu(station),
                              onToggleFavorite: () =>
                                  stationLibrary.toggleFavorite(station.id),
                            );
                          },
                        ),
                ),
                _NowPlayingBar(
                  onPlayPause: radioPlayer.togglePlayPause,
                  onStop: radioPlayer.stop,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NowPlayingBar extends StatelessWidget {
  const _NowPlayingBar({
    required this.onPlayPause,
    required this.onStop,
  });

  final VoidCallback onPlayPause;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final player = radioPlayer;
    final station = player.station;
    final track = player.nowPlaying;
    final hasTrack = track != null;
    final title = hasTrack
        ? track.displayTitle
        : (station?.name ?? 'тишина в эфире');
    String subtitle;
    if (player.status == RadioPlaybackStatus.error) {
      subtitle = player.errorMessage ?? 'не удалось открыть поток';
    } else if (player.status == RadioPlaybackStatus.loading && !hasTrack) {
      subtitle = 'подключение…';
    } else if (hasTrack) {
      subtitle = [
        ?track.displayArtist,
        if (station != null) station.name,
      ].join(' · ');
    } else if (player.isActive) {
      subtitle = 'нет данных о треке';
    } else {
      subtitle = station?.genre ?? 'выберите станцию';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.line)),
        color: palette.codeBar.withValues(alpha: 0.55),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _TransportButton(
                icon: player.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: palette.accent,
                onPressed: station == null && !player.isActive
                    ? null
                    : onPlayPause,
              ),
              const SizedBox(width: 4),
              _TransportButton(
                icon: Icons.stop_rounded,
                color: palette.muted,
                onPressed: player.isActive ? onStop : null,
              ),
              const SizedBox(width: 8),
              if (station != null) ...[
                StationLogo(
                  station: station,
                  size: 40,
                  imageUrl: track?.artworkUrl,
                ),
                const SizedBox(width: 8),
              ],
              if (player.status == RadioPlaybackStatus.loading)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: palette.accent,
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: palette.ink,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'Menlo',
                        color: player.status == RadioPlaybackStatus.error
                            ? palette.red
                            : palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: [
              _TransportButton(
                icon: Icons.graphic_eq_rounded,
                color: equalizerService.enabled
                    ? palette.accent
                    : palette.muted,
                onPressed: () => showEqualizerSheet(context),
              ),
              Icon(Icons.volume_down_rounded, size: 14, color: palette.muted),
              Expanded(
                child: Slider(
                  value: player.volume,
                  onChanged: player.setVolume,
                ),
              ),
              Icon(Icons.volume_up_rounded, size: 14, color: palette.muted),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: color),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      splashRadius: 16,
    );
  }
}

class _StationTile extends StatefulWidget {
  const _StationTile({
    required this.station,
    required this.index,
    required this.selected,
    required this.playing,
    required this.onTap,
    required this.onShowMenu,
    required this.onToggleFavorite,
  });

  final RadioStation station;
  final int index;
  final bool selected;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onShowMenu;
  final VoidCallback onToggleFavorite;

  @override
  State<_StationTile> createState() => _StationTileState();
}

class _StationTileState extends State<_StationTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final station = widget.station;
    final typeColor = GenreCatalog.colorFor(station.genre, palette);
    final highlighted = widget.selected || _hovered || widget.playing;
    final shortcut = widget.index < 9 ? '${widget.index + 1}' : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onShowMenu,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.fromLTRB(0, 10, 4, 10),
            decoration: BoxDecoration(
              color: highlighted
                  ? palette.current.withValues(alpha: 0.55)
                  : palette.bgElevated.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.playing || widget.selected
                    ? typeColor.withValues(alpha: 0.75)
                    : highlighted
                        ? typeColor.withValues(alpha: 0.45)
                        : palette.line.withValues(alpha: 0.75),
                width: widget.selected || widget.playing ? 1.4 : 1,
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 3.5,
                    margin: const EdgeInsets.only(left: 2, right: 8),
                    decoration: BoxDecoration(
                      color: typeColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  if (shortcut != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: palette.current.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: palette.line),
                          ),
                          child: Text(
                            shortcut,
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'Menlo',
                              fontWeight: FontWeight.w600,
                              color: palette.mutedBright,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Align(
                      alignment: Alignment.center,
                      child: StationLogo(station: station, size: 36),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          station.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: palette.ink,
                          ),
                        ),
                        if (station.hasComment) ...[
                          const SizedBox(height: 3),
                          Text(
                            station.comment!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: palette.muted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: typeColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                station.genre,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontFamily: 'Menlo',
                                  color: typeColor,
                                ),
                              ),
                            ),
                            if (widget.playing) ...[
                              Text(
                                '  ·  ',
                                style:
                                    TextStyle(fontSize: 11, color: palette.muted),
                              ),
                              Text(
                                radioPlayer.status == RadioPlaybackStatus.loading
                                    ? 'подключение…'
                                    : 'в эфире',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontFamily: 'Menlo',
                                  color: palette.green,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      station.isFavorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 18,
                      color: station.isFavorite ? palette.accent : palette.muted,
                    ),
                    onPressed: widget.onToggleFavorite,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    splashRadius: 14,
                  ),
                  IconButton(
                    icon: Icon(Icons.more_vert, size: 18, color: palette.muted),
                    onPressed: widget.onShowMenu,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    splashRadius: 14,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.accentColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = accentColor ?? palette.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.18)
                : palette.bgElevated.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.7) : palette.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: selected ? color : palette.muted),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Menlo',
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? color : palette.mutedBright,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasText = controller.text.isNotEmpty;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.bgElevated.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: palette.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(fontSize: 13, height: 1.2, color: palette.ink),
              cursorColor: palette.accent,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Поиск станций…',
                hintStyle: TextStyle(
                  color: palette.muted,
                  fontSize: 13,
                  height: 1.2,
                ),
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onChanged,
            ),
          ),
          if (hasText)
            GestureDetector(
              onTap: onClear,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.close, size: 15, color: palette.muted),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: palette.current.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: palette.line),
              ),
              child: Text(
                '⌘F',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'Menlo',
                  color: palette.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 42, color: palette.muted.withValues(alpha: 0.7)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.mutedBright, fontSize: 13),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return IconButton(
      icon: Icon(icon, size: 16, color: palette.muted),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      splashRadius: 16,
    );
  }
}

class _StationDraft {
  const _StationDraft({
    required this.name,
    required this.url,
    required this.genre,
    required this.comment,
    required this.logoUrl,
  });

  final String name;
  final String url;
  final String genre;
  final String comment;
  final String logoUrl;
}

class _StationEditorDialog extends StatefulWidget {
  const _StationEditorDialog({
    required this.genres,
    this.existing,
  });

  final RadioStation? existing;
  final List<String> genres;

  @override
  State<_StationEditorDialog> createState() => _StationEditorDialogState();
}

class _StationEditorDialogState extends State<_StationEditorDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _url =
      TextEditingController(text: widget.existing?.url ?? '');
  late final TextEditingController _genre =
      TextEditingController(text: widget.existing?.genre ?? GenreCatalog.other);
  late final TextEditingController _comment =
      TextEditingController(text: widget.existing?.comment ?? '');
  late final TextEditingController _logo =
      TextEditingController(text: widget.existing?.logoUrl ?? '');

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _genre.dispose();
    _comment.dispose();
    _logo.dispose();
    super.dispose();
  }

  InputDecoration _decoration(
    AppPalette palette,
    String label, {
    String? helper,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: palette.muted, fontSize: 12),
      helperText: helper,
      helperStyle: TextStyle(color: palette.muted, fontSize: 11),
      filled: true,
      fillColor: palette.bgElevated.withValues(alpha: 0.6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: palette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: palette.accent),
      ),
      contentPadding: const EdgeInsets.all(12),
    );
  }

  void _submit() {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme) return;
    Navigator.pop(
      context,
      _StationDraft(
        name: name,
        url: url,
        genre: _genre.text,
        comment: _comment.text,
        logoUrl: _logo.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Новая станция' : 'Изменить станцию'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                style: TextStyle(fontSize: 13, color: palette.ink),
                decoration: _decoration(palette, 'Название'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Menlo',
                  color: palette.ink,
                ),
                decoration: _decoration(palette, 'URL потока'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _genre,
                style: TextStyle(fontSize: 13, color: palette.ink),
                decoration: _decoration(palette, 'Жанр'),
              ),
              if (widget.genres.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final genre in widget.genres)
                      ActionChip(
                        label: Text(genre),
                        onPressed: () => setState(() => _genre.text = genre),
                        backgroundColor:
                            palette.bgElevated.withValues(alpha: 0.7),
                        side: BorderSide(color: palette.line),
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Menlo',
                          color: palette.mutedBright,
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _comment,
                style: TextStyle(fontSize: 13, color: palette.ink),
                decoration: _decoration(palette, 'Комментарий'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _logo,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Menlo',
                  color: palette.ink,
                ),
                decoration: _decoration(
                  palette,
                  'URL логотипа (необязательно)',
                  helper: 'Если пусто — логотип найдётся по ссылке потока',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Отмена', style: TextStyle(color: palette.muted)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text('Сохранить', style: TextStyle(color: palette.accent)),
        ),
      ],
    );
  }
}

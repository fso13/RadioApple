import 'package:flutter/material.dart';
import 'package:radio_mac/models/equalizer_preset.dart';
import 'package:radio_mac/services/equalizer_service.dart';
import 'package:radio_mac/theme/app_palette.dart';

Future<void> showEqualizerSheet(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const EqualizerSheet(),
  );
}

class EqualizerSheet extends StatelessWidget {
  const EqualizerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: const Text('Эквалайзер'),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      content: SizedBox(
        width: 360,
        child: AnimatedBuilder(
          animation: equalizerService,
          builder: (context, _) {
            final eq = equalizerService;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Включить',
                    style: TextStyle(fontSize: 13, color: palette.ink),
                  ),
                  subtitle: Text(
                    eq.enabled
                        ? '10 полос, пресеты и своя кривая'
                        : 'Поток идёт без коррекции',
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                  value: eq.enabled,
                  onChanged: eq.setEnabled,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final preset in EqualizerCatalog.presets)
                      _PresetChip(
                        label: preset.label,
                        selected: eq.presetId == preset.id,
                        onTap: () => eq.applyPreset(preset.id),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 168,
                  child: Opacity(
                    opacity: eq.enabled ? 1 : 0.45,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < EqualizerCatalog.bandCount; i++)
                          Expanded(
                            child: _BandSlider(
                              label: EqualizerCatalog.labelForHz(
                                EqualizerCatalog.frequencies[i],
                              ),
                              value: eq.gains[i],
                              onChanged: eq.enabled
                                  ? (value) => eq.setBand(i, value)
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: eq.resetFlat,
                    child: const Text('Сбросить'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Закрыть', style: TextStyle(color: palette.accent)),
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.18)
                : palette.bgElevated.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? palette.accent.withValues(alpha: 0.7)
                  : palette.line,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'Menlo',
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? palette.accent : palette.mutedBright,
            ),
          ),
        ),
      ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        Text(
          value >= 0 ? '+${value.round()}' : '${value.round()}',
          style: TextStyle(
            fontSize: 9,
            fontFamily: 'Menlo',
            color: palette.muted,
          ),
        ),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              min: EqualizerCatalog.minGain,
              max: EqualizerCatalog.maxGain,
              value: value,
              onChanged: onChanged,
            ),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontFamily: 'Menlo',
            color: palette.mutedBright,
          ),
        ),
      ],
    );
  }
}

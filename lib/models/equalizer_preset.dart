class EqualizerPreset {
  const EqualizerPreset({
    required this.id,
    required this.label,
    required this.gains,
  });

  final String id;
  final String label;

  /// 10 bands in dB, order: 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k.
  final List<double> gains;
}

abstract final class EqualizerCatalog {
  static const bandCount = 10;
  static const minGain = -12.0;
  static const maxGain = 12.0;
  static const frequencies = <int>[
    32,
    64,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000,
  ];

  static const customId = 'custom';
  static const flatId = 'flat';

  static const custom = EqualizerPreset(
    id: customId,
    label: 'Свой',
    gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  );

  static const presets = <EqualizerPreset>[
    EqualizerPreset(
      id: flatId,
      label: 'Плоский',
      gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    ),
    custom,
    EqualizerPreset(
      id: 'bass',
      label: 'Бас',
      gains: [8, 6, 4, 2, 0, -1, -2, -2, -2, -2],
    ),
    EqualizerPreset(
      id: 'treble',
      label: 'Высокие',
      gains: [-3, -2, -1, 0, 1, 2, 4, 6, 7, 8],
    ),
    EqualizerPreset(
      id: 'voice',
      label: 'Голос',
      gains: [-4, -3, -1, 2, 5, 5, 4, 1, -2, -4],
    ),
    EqualizerPreset(
      id: 'rock',
      label: 'Рок',
      gains: [5, 4, 2, 0, -2, -1, 1, 3, 4, 5],
    ),
    EqualizerPreset(
      id: 'pop',
      label: 'Поп',
      gains: [-1, 2, 4, 3, 0, -1, -1, 1, 3, 4],
    ),
    EqualizerPreset(
      id: 'jazz',
      label: 'Джаз',
      gains: [3, 2, 0, 1, -2, -2, 0, 1, 3, 4],
    ),
    EqualizerPreset(
      id: 'electronic',
      label: 'Электро',
      gains: [6, 5, 1, 0, -2, 2, 1, 2, 4, 6],
    ),
    EqualizerPreset(
      id: 'classical',
      label: 'Классика',
      gains: [5, 3, 1, 0, 0, 0, -1, -1, 2, 4],
    ),
    EqualizerPreset(
      id: 'spoken',
      label: 'Речь',
      gains: [-6, -4, 0, 3, 4, 4, 2, 0, -2, -5],
    ),
  ];

  static EqualizerPreset byId(String id) {
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return presets.first;
  }

  static String labelForHz(int hz) {
    if (hz >= 1000) return '${hz ~/ 1000}k';
    return '$hz';
  }

  static List<double> clampGains(List<double> raw) {
    final next = List<double>.filled(bandCount, 0);
    for (var i = 0; i < bandCount; i++) {
      final value = i < raw.length ? raw[i] : 0.0;
      next[i] = value.clamp(minGain, maxGain);
    }
    return next;
  }

  static bool sameGains(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.05) return false;
    }
    return true;
  }
}

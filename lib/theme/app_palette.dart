import 'package:flutter/material.dart';

/// Dracula-inspired palette from fso13 / CopyPastePlus.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.bgElevated,
    required this.bgSoft,
    required this.bgDeep,
    required this.current,
    required this.ink,
    required this.muted,
    required this.mutedBright,
    required this.accent,
    required this.accentHover,
    required this.accentPink,
    required this.cyan,
    required this.green,
    required this.orange,
    required this.yellow,
    required this.red,
    required this.line,
    required this.codeBar,
    required this.glowAccent,
    required this.glowPink,
    required this.shadow,
  });

  final Color bg;
  final Color bgElevated;
  final Color bgSoft;
  final Color bgDeep;
  final Color current;
  final Color ink;
  final Color muted;
  final Color mutedBright;
  final Color accent;
  final Color accentHover;
  final Color accentPink;
  final Color cyan;
  final Color green;
  final Color orange;
  final Color yellow;
  final Color red;
  final Color line;
  final Color codeBar;
  final Color glowAccent;
  final Color glowPink;
  final Color shadow;

  static const dark = AppPalette(
    bg: Color(0xFF282A36),
    bgElevated: Color(0xFF21222C),
    bgSoft: Color(0xFF2D303E),
    bgDeep: Color(0xFF21222C),
    current: Color(0xFF44475A),
    ink: Color(0xFFF8F8F2),
    muted: Color(0xFF6272A4),
    mutedBright: Color(0xFFC7CCE0),
    accent: Color(0xFFBD93F9),
    accentHover: Color(0xFFCBB2F9),
    accentPink: Color(0xFFFF79C6),
    cyan: Color(0xFF8BE9FD),
    green: Color(0xFF50FA7B),
    orange: Color(0xFFFFB86C),
    yellow: Color(0xFFF1FA8C),
    red: Color(0xFFFF5555),
    line: Color(0xFF44475A),
    codeBar: Color(0xFF191A21),
    glowAccent: Color(0x1FBD93F9),
    glowPink: Color(0x14FF79C6),
    shadow: Color(0x59000000),
  );

  static const light = AppPalette(
    bg: Color(0xFFF4F5FA),
    bgElevated: Color(0xFFFFFFFF),
    bgSoft: Color(0xFFFFFFFF),
    bgDeep: Color(0xFFE9EBF4),
    current: Color(0xFFD5D8E5),
    ink: Color(0xFF282A36),
    muted: Color(0xFF6272A4),
    mutedBright: Color(0xFF44475A),
    accent: Color(0xFF7C5CBF),
    accentHover: Color(0xFF6B4DB0),
    accentPink: Color(0xFFC44D8F),
    cyan: Color(0xFF0F7A8A),
    green: Color(0xFF2D8A57),
    orange: Color(0xFFB7791F),
    yellow: Color(0xFF9A8610),
    red: Color(0xFFC43C3C),
    line: Color(0xFFD5D8E5),
    codeBar: Color(0xFFECEEF5),
    glowAccent: Color(0x1F7C5CBF),
    glowPink: Color(0x14C44D8F),
    shadow: Color(0x1F282A36),
  );

  @override
  AppPalette copyWith({
    Color? bg,
    Color? bgElevated,
    Color? bgSoft,
    Color? bgDeep,
    Color? current,
    Color? ink,
    Color? muted,
    Color? mutedBright,
    Color? accent,
    Color? accentHover,
    Color? accentPink,
    Color? cyan,
    Color? green,
    Color? orange,
    Color? yellow,
    Color? red,
    Color? line,
    Color? codeBar,
    Color? glowAccent,
    Color? glowPink,
    Color? shadow,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      bgElevated: bgElevated ?? this.bgElevated,
      bgSoft: bgSoft ?? this.bgSoft,
      bgDeep: bgDeep ?? this.bgDeep,
      current: current ?? this.current,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      mutedBright: mutedBright ?? this.mutedBright,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentPink: accentPink ?? this.accentPink,
      cyan: cyan ?? this.cyan,
      green: green ?? this.green,
      orange: orange ?? this.orange,
      yellow: yellow ?? this.yellow,
      red: red ?? this.red,
      line: line ?? this.line,
      codeBar: codeBar ?? this.codeBar,
      glowAccent: glowAccent ?? this.glowAccent,
      glowPink: glowPink ?? this.glowPink,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      bgElevated: Color.lerp(bgElevated, other.bgElevated, t)!,
      bgSoft: Color.lerp(bgSoft, other.bgSoft, t)!,
      bgDeep: Color.lerp(bgDeep, other.bgDeep, t)!,
      current: Color.lerp(current, other.current, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      mutedBright: Color.lerp(mutedBright, other.mutedBright, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentPink: Color.lerp(accentPink, other.accentPink, t)!,
      cyan: Color.lerp(cyan, other.cyan, t)!,
      green: Color.lerp(green, other.green, t)!,
      orange: Color.lerp(orange, other.orange, t)!,
      yellow: Color.lerp(yellow, other.yellow, t)!,
      red: Color.lerp(red, other.red, t)!,
      line: Color.lerp(line, other.line, t)!,
      codeBar: Color.lerp(codeBar, other.codeBar, t)!,
      glowAccent: Color.lerp(glowAccent, other.glowAccent, t)!,
      glowPink: Color.lerp(glowPink, other.glowPink, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}

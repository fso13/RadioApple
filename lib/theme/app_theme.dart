import 'package:flutter/material.dart';
import 'package:radio_mac/theme/app_palette.dart';

class AppTheme {
  static ThemeData light() => _build(AppPalette.light, Brightness.light);

  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette palette, Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
    );

    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: palette.accent,
        onPrimary:
            brightness == Brightness.dark ? palette.bg : Colors.white,
        secondary: palette.accentPink,
        onSecondary:
            brightness == Brightness.dark ? palette.bg : Colors.white,
        error: palette.red,
        onError: Colors.white,
        surface: palette.bgElevated,
        onSurface: palette.ink,
        outline: palette.line,
      ),
      extensions: [palette],
      dialogTheme: DialogThemeData(
        backgroundColor: palette.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: palette.line),
        ),
        titleTextStyle: TextStyle(
          color: palette.ink,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          color: palette.mutedBright,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.bgElevated,
        contentTextStyle: TextStyle(color: palette.ink, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: palette.line),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return palette.accent;
          return palette.muted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.accent.withValues(alpha: 0.35);
          }
          return palette.current;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accent,
        inactiveTrackColor: palette.current,
        thumbColor: palette.accent,
        overlayColor: palette.accent.withValues(alpha: 0.15),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor:
              brightness == Brightness.dark ? palette.bg : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.ink,
          side: BorderSide(color: palette.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: palette.accent),
      ),
      dividerColor: palette.line,
      cardColor: palette.bgElevated,
      listTileTheme: ListTileThemeData(
        iconColor: palette.mutedBright,
        textColor: palette.ink,
      ),
    );
  }
}

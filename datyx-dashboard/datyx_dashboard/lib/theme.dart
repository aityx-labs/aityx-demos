import 'package:flutter/material.dart';

/// The aityx dark palette, as every demo's app: near-black with a violet
/// tint, light gray text, and an orange accent.
abstract final class Aityx {
  static const bg0 = Color(0xFF151418);
  static const bg = Color(0xFF17161A);
  static const bg1 = Color(0xFF201E24);
  static const bg2 = Color(0xFF2A272E);
  static const border = Color(0xFF37333C);
  static const dim = Color(0xFF47474D);

  static const fg0 = Color(0xFFFFFFFF);
  static const fg = Color(0xFFEFF2F4);
  static const muted = Color(0xFFA9ACB6);

  static const orange = Color(0xFFE36742);
  static const orangeLight = Color(0xFFEB7B58);
  static const green = Color(0xFF4CC38A);
  static const amber = Color(0xFFE8B04B);
  static const red = Color(0xFFF0506E);
}

/// The page is the near-black background; panels and cards step up through
/// bg1 and bg2, and the primary color is the orange accent.
ThemeData aityxDarkTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Aityx.orange,
    onPrimary: Aityx.fg0,
    primaryContainer: Aityx.bg2,
    onPrimaryContainer: Aityx.orangeLight,
    secondary: Aityx.green,
    onSecondary: Aityx.bg,
    secondaryContainer: Aityx.bg2,
    onSecondaryContainer: Aityx.fg,
    tertiary: Aityx.amber,
    onTertiary: Aityx.bg,
    tertiaryContainer: Aityx.bg2,
    onTertiaryContainer: Aityx.amber,
    error: Aityx.red,
    onError: Aityx.bg,
    errorContainer: Aityx.bg2,
    onErrorContainer: Aityx.red,
    surface: Aityx.bg,
    onSurface: Aityx.fg,
    onSurfaceVariant: Aityx.muted,
    surfaceContainerLowest: Aityx.bg0,
    surfaceContainerLow: Aityx.bg1,
    surfaceContainer: Aityx.bg1,
    surfaceContainerHigh: Aityx.bg2,
    surfaceContainerHighest: Aityx.bg2,
    outline: Aityx.border,
    outlineVariant: Aityx.dim,
    inverseSurface: Aityx.fg,
    onInverseSurface: Aityx.bg,
    inversePrimary: Aityx.orangeLight,
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    dividerColor: Aityx.border,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: Aityx.bg,
      foregroundColor: Aityx.fg,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: Aityx.fg0,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: const CardThemeData(
      color: Aityx.bg1,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Aityx.border),
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Aityx.bg0,
      border: OutlineInputBorder(borderSide: BorderSide(color: Aityx.border)),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Aityx.border),
      ),
    ),
  );
}

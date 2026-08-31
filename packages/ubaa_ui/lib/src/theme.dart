import 'package:flutter/material.dart';

/// 与旧版 Material 3 体验相近的应用主题。
class UbaaTheme {
  const UbaaTheme._();

  static const Color seedColor = Color(0xFF536AA3);

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
    ),
    cardTheme: const CardThemeData(margin: EdgeInsets.zero),
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    ),
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
    ),
    cardTheme: const CardThemeData(margin: EdgeInsets.zero),
  );
}

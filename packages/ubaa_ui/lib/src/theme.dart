import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// 共享 Material 3 设计变量；宿主只选择亮度，不持久化偏好。
class UbaaTheme {
  const UbaaTheme._();

  static const locale = Locale('zh', 'CN');
  static const supportedLocales = [locale];
  static const localizationsDelegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static const Color seedColor = Color(0xFF536AA3);
  static const double cardRadius = 16;
  static const double controlRadius = 12;

  static double pagePadding(double width) => width < 600
      ? 16
      : width < 1000
      ? 24
      : 32;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors =
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: brightness,
        ).copyWith(
          primary: dark ? const Color(0xFFB7C7F4) : seedColor,
          onPrimary: dark ? const Color(0xFF24365F) : Colors.white,
          primaryContainer: dark
              ? const Color(0xFF343F5B)
              : const Color(0xFFE6EBF8),
          onPrimaryContainer: dark
              ? const Color(0xFFE5E7F0)
              : const Color(0xFF253B6B),
          secondaryContainer: dark
              ? const Color(0xFF343F5B)
              : const Color(0xFFE6EBF8),
          onSecondaryContainer: dark
              ? const Color(0xFFE5E7F0)
              : const Color(0xFF253B6B),
          surface: dark ? const Color(0xFF171A22) : const Color(0xFFF6F7FB),
          surfaceContainerLowest: dark ? const Color(0xFF171A22) : Colors.white,
          surfaceContainerLow: dark ? const Color(0xFF242833) : Colors.white,
          surfaceContainer: dark
              ? const Color(0xFF1C202B)
              : const Color(0xFFEDF0F8),
          surfaceContainerHigh: dark
              ? const Color(0xFF292E3B)
              : const Color(0xFFF0F3FA),
          surfaceContainerHighest: dark
              ? const Color(0xFF343B4B)
              : const Color(0xFFE6EBF5),
          onSurface: dark ? const Color(0xFFE5E7F0) : const Color(0xFF252832),
          onSurfaceVariant: dark
              ? const Color(0xFFB7BDCE)
              : const Color(0xFF606575),
          outlineVariant: dark
              ? const Color(0xFF383F50)
              : const Color(0xFFE0E4ED),
        );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceContainer,
        indicatorColor: colors.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? colors.onSurface
                : colors.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surfaceContainer,
        indicatorColor: colors.secondaryContainer,
        useIndicator: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      hoverColor: colors.primary.withValues(alpha: 0.04),
      focusColor: colors.primary.withValues(alpha: 0.10),
      // 当前复选框、开关均属于整行选项；反馈由外层选项行统一绘制。
      checkboxTheme: const CheckboxThemeData(
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
        splashRadius: 0,
      ),
      switchTheme: const SwitchThemeData(
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
        splashRadius: 0,
      ),
      listTileTheme: ListTileThemeData(shape: controlShape),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: controlShape),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: colors.onSurface,
          fontSize: 26,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
        filled: true,
        fillColor: colors.surfaceContainerLow,
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        elevation: 0,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: controlShape,
          minimumSize: const Size(48, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: controlShape,
          minimumSize: const Size(48, 48),
        ),
      ),
    );
  }
}

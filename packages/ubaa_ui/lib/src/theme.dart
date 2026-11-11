import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'shared/monday_first_localizations.dart';

/// 共享 Material 3 设计变量；宿主只选择亮度，不持久化偏好。
class UbaaTheme {
  const UbaaTheme._();

  static const locale = Locale('zh', 'CN');
  static const supportedLocales = [locale];
  static const localizationsDelegates = [
    // 排在官方委托前面：同类型委托取第一个，中文日期选择器改为周一开头。
    UiMondayFirstLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  /// 无头渲染（如商店截图）注入的字体族；测试字体环境不解析未指定字体族的文本。
  /// 生产始终为空，沿用各平台系统字体。
  @visibleForTesting
  static String? debugFontFamily;

  static const Color seedColor = Color(0xFF1976D2);
  static const double pageMaxWidth = 1040;
  static const double cardRadius = 16;
  static const double controlRadius = 12;

  /// 成功与临近截止的语义色；Material 配色没有这两类，统一在此定义。
  static Color success(ColorScheme colors) =>
      colors.brightness == Brightness.dark
      ? const Color(0xFF8BD5A8)
      : const Color(0xFF2E7D4F);

  static Color warning(ColorScheme colors) =>
      colors.brightness == Brightness.dark
      ? const Color(0xFFFFBD75)
      : const Color(0xFF9A4D00);

  /// 面板、对话框内的分组底色：半透明叠色，在页面、底部面板和对话框上都看得出边界。
  static Color insetFill(ColorScheme colors) =>
      colors.onSurface.withValues(alpha: .05);

  static double pagePadding(double width) => width < 600
      ? 16
      : width < 1000
      ? 24
      : 32;

  static EdgeInsets pageInsets(
    BuildContext context, {
    double? top,
    double? bottom,
  }) {
    final gutter = pagePadding(MediaQuery.sizeOf(context).width);
    return EdgeInsets.fromLTRB(gutter, top ?? gutter, gutter, bottom ?? gutter);
  }

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    // 浅底与正文建立层次，图标蓝串联导航、来源和操作。
    // 明暗主题按角色配对，区分品牌强调与普通状态。
    final accentContainer = dark
        ? const Color(0xFF183F64)
        : const Color(0xFFE3F0FC);
    final onAccentContainer = dark
        ? const Color(0xFFB8DAFC)
        : const Color(0xFF125EA7);
    final colors =
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.neutral,
        ).copyWith(
          primary: dark ? const Color(0xFF83BEF7) : seedColor,
          onPrimary: dark ? const Color(0xFF082F49) : Colors.white,
          primaryContainer: accentContainer,
          onPrimaryContainer: onAccentContainer,
          secondary: dark ? const Color(0xFFC2C2C2) : const Color(0xFF596B7E),
          onSecondary: dark ? const Color(0xFF242424) : Colors.white,
          secondaryContainer: accentContainer,
          onSecondaryContainer: onAccentContainer,
          surface: dark ? const Color(0xFF111C29) : const Color(0xFFFCFDFF),
          surfaceContainerLowest: dark ? const Color(0xFF0D1621) : Colors.white,
          surfaceContainerLow: dark ? const Color(0xFF1C2B3D) : Colors.white,
          surfaceContainer: dark
              ? const Color(0xFF14283D)
              : const Color(0xFFEAF3FC),
          surfaceContainerHigh: dark
              ? const Color(0xFF27374A)
              : const Color(0xFFF1F4F7),
          surfaceContainerHighest: dark
              ? const Color(0xFF34465B)
              : const Color(0xFFE5EBF2),
          onSurface: dark ? const Color(0xFFEAF3FC) : const Color(0xFF242424),
          onSurfaceVariant: dark
              ? const Color(0xFFB8C7D9)
              : const Color(0xFF596B7E),
          outline: dark ? const Color(0xFF8A8A8A) : const Color(0xFF757575),
          outlineVariant: dark
              ? const Color(0xFF364B62)
              : const Color(0xFFDBE5EF),
          inverseSurface: dark
              ? const Color(0xFFEAF3FC)
              : const Color(0xFF303030),
          onInverseSurface: dark
              ? const Color(0xFF242424)
              : const Color(0xFFF5F5F5),
          inversePrimary: dark ? seedColor : const Color(0xFF83BEF7),
          surfaceTint: dark ? const Color(0xFF83BEF7) : seedColor,
        );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );
    return ThemeData(
      adaptations: [_AppleSwitchAdaptation(colors.primary)],
      useMaterial3: true,
      fontFamily: debugFontFamily,
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
                ? FontWeight.w500
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? colors.onSurface
                : colors.onSurfaceVariant,
          ),
        ),
      ),
      // 选中标签已有底色区分，不再加对钩，宽度也不随选中跳动。
      chipTheme: const ChipThemeData(showCheckmark: false),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surfaceContainer,
        indicatorColor: colors.secondaryContainer,
        useIndicator: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      // 日期选择与其他对话框同一底色。
      datePickerTheme: DatePickerThemeData(
        backgroundColor: colors.surfaceContainerLow,
        rangePickerBackgroundColor: colors.surfaceContainerLow,
      ),
      // 菜单从按钮下方展开，不盖住触发它的按钮。
      popupMenuTheme: PopupMenuThemeData(
        position: PopupMenuPosition.under,
        color: colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        style: TextButton.styleFrom(
          shape: controlShape,
          foregroundColor: colors.onPrimaryContainer,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: debugFontFamily,
          color: colors.onSurface,
          fontSize: 26,
          fontWeight: FontWeight.w500,
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
          foregroundColor: colors.onPrimaryContainer,
          minimumSize: const Size(48, 48),
        ),
      ),
    );
  }
}

/// Apple 平台的自适应开关默认是系统绿色且忽略 [SwitchThemeData]；改为主色，
/// 与 macOS 跟随强调色的原生开关一致。
class _AppleSwitchAdaptation extends Adaptation<SwitchThemeData> {
  const _AppleSwitchAdaptation(this.primary);
  final Color primary;
  @override
  SwitchThemeData adapt(ThemeData theme, SwitchThemeData defaultValue) =>
      switch (theme.platform) {
        TargetPlatform.iOS || TargetPlatform.macOS => SwitchThemeData(
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? primary : null,
          ),
        ),
        _ => defaultValue,
      };
}

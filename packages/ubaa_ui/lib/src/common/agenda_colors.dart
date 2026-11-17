import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../features/schedule/colors.dart' show ScheduleCourseColors;
import '../theme.dart';

/// 首页与日程共用来源色；自建事项优先使用用户颜色，课程按名称分色。
Color uiAgendaSourceColor(
  FeatureId? feature,
  ColorScheme colors, {
  String title = '',
  String? customColor,
}) {
  if (customColor != null &&
      RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(customColor)) {
    return Color(0xFF000000 | int.parse(customColor.substring(1), radix: 16));
  }
  return switch (feature) {
    FeatureId.schedule => ScheduleCourseColors.accent(title, colors.brightness),
    FeatureId.spoc || FeatureId.judge => const Color(0xFFE8833A),
    FeatureId.exam => colors.error,
    FeatureId.bykc => UbaaTheme.category(const Color(0xFF8E5CD9), colors),
    FeatureId.cgyy => const Color(0xFF2E9E8F),
    _ => colors.tertiary,
  };
}

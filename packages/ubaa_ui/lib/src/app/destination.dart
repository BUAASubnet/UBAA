import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 仅用于界面分组；领域标识及读取合同保持独立。
enum UiDestination {
  home('首页', Icons.home_outlined, Icons.home, []),
  study('学习', Icons.school_outlined, Icons.school, [
    FeatureId.schedule,
    FeatureId.signin,
    FeatureId.spoc,
    FeatureId.judge,
    FeatureId.bykc,
    FeatureId.exam,
    FeatureId.grades,
    FeatureId.evaluation,
  ]),
  agenda('日程', Icons.event_outlined, Icons.event, []),
  campus('校园', Icons.apartment_outlined, Icons.apartment, [
    FeatureId.classroom,
    FeatureId.libbook,
    FeatureId.cgyy,
    FeatureId.ygdk,
  ]),
  me('我的', Icons.person_outline, Icons.person, []),
  settings('设置', Icons.settings_outlined, Icons.settings, []);

  const UiDestination(this.label, this.icon, this.selectedIcon, this.features);
  final String label;
  final IconData icon, selectedIcon;
  final List<FeatureId> features;

  static UiDestination forFeature(FeatureId feature) => values.firstWhere(
    (destination) => destination.features.contains(feature),
  );
}

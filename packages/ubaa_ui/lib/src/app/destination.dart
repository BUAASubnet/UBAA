import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 仅用于界面分组；领域标识及读取合同保持独立。
enum UiDestination {
  home('首页', Icons.home_outlined, Icons.home, []),
  academic('学业', Icons.school_outlined, Icons.school, [
    FeatureId.schedule,
    FeatureId.exam,
    FeatureId.grades,
    FeatureId.classroom,
    FeatureId.evaluation,
  ]),
  coursework('课程与作业', Icons.assignment_outlined, Icons.assignment, [
    FeatureId.spoc,
    FeatureId.judge,
    FeatureId.bykc,
    FeatureId.signin,
  ]),
  campus('校园服务', Icons.apartment_outlined, Icons.apartment, [
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

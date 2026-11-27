import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import 'study_landing.dart' show CourseHubLanding;

/// 学习页根页面：有课程中心时显示按课程组织的学习页，否则沿用功能宫格。
Widget buildStudyRoot({
  required Widget grid,
  required ValueListenable<CourseHubSnapshot>? courseHub,
  required ValueChanged<String> onCourse,
  required ValueChanged<FeatureId> onOpenFeature,
  required Future<void> Function()? onRefresh,
  required VoidCallback onAssignments,
  required VoidCallback onSources,
}) {
  final source = courseHub;
  if (source == null) return grid;
  return ValueListenableBuilder<CourseHubSnapshot>(
    valueListenable: source,
    builder: (_, snapshot, _) => CourseHubLanding(
      snapshot: snapshot,
      onOpenFeature: onOpenFeature,
      onOpenCourse: onCourse,
      onOpenAssignments: onAssignments,
      onOpenSources: onSources,
      onRefresh: onRefresh ?? () async {},
    ),
  );
}

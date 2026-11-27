import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../common/section.dart' show UiEntryCard, UiEntryList;
import '../../shared/feature_icons.dart' show uiFeatureIcon;
import '../../theme.dart' show UbaaTheme;

export 'assignments_page.dart' show CourseHubAssignmentsPage;
export 'course_page.dart' show CourseHubCoursePage;

typedef SetJudgeLink =
    Future<void> Function(String courseKey, String judgeCourseId, bool linked);

/// 按来源浏览：保留原来按学校系统划分的三个入口，承接对不上课程的内容和往年希冀。
class CourseHubSourcesPage extends StatelessWidget {
  const CourseHubSourcesPage({
    super.key,
    required this.snapshot,
    required this.onOpenFeature,
  });
  final CourseHubSnapshot snapshot;
  final ValueChanged<FeatureId> onOpenFeature;

  static const _entries = [
    (FeatureId.spoc, '按课程分组的全部 SPOC 作业'),
    (FeatureId.judge, '全部希冀作业，可加载往年记录'),
    (FeatureId.signin, '今天每节课的上课状态与签到'),
  ];

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('course-hub-sources'),
    padding: UbaaTheme.pageInsets(context, top: 8, bottom: 24),
    children: [
      UiEntryList(
        children: [
          for (final (feature, subtitle) in _entries)
            UiEntryCard(
              key: ValueKey('course-hub-source-${feature.name}'),
              title: feature.title,
              icon: uiFeatureIcon(feature),
              subtitle: subtitle,
              onTap: () => onOpenFeature(feature),
            ),
        ],
      ),
    ],
  );
}

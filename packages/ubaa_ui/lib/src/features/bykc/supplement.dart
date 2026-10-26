import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'display.dart' show BykcInfoLine, uiBykcDate;
import 'section.dart' show BykcSection;

List<Widget> uiBykcContactFields(BykcCourseSupplement? supplement) => [
  BykcInfoLine('联系人', supplement?.courseContact),
  BykcInfoLine('联系电话', supplement?.courseContactMobile),
  BykcInfoLine('开课单位', supplement?.organizerCollegeName),
];

List<Widget> uiBykcSupplementSections(BykcCoursePresentation course) {
  final supplement = course.supplement;
  if (supplement == null) return const [];
  String? audience(List<String> values) =>
      values.isEmpty ? null : values.join('、');
  return [
    if (supplement.descriptionPlainText case final description?) ...[
      const SizedBox(height: 12),
      BykcSection('课程简介', [Text(description)]),
    ],
    if (course.audienceCampuses.isNotEmpty ||
        supplement.audienceColleges.isNotEmpty ||
        supplement.audienceTerms.isNotEmpty ||
        supplement.audienceGroups.isNotEmpty) ...[
      const SizedBox(height: 12),
      BykcSection('适用范围', [
        BykcInfoLine('校区', audience(course.audienceCampuses)),
        BykcInfoLine('学院', audience(supplement.audienceColleges)),
        BykcInfoLine('年级', audience(supplement.audienceTerms)),
        BykcInfoLine('人群', audience(supplement.audienceGroups)),
      ]),
    ],
  ];
}

List<Widget> uiBykcDisplaySignFields(BykcSignDisplayConfig? config) => [
  BykcInfoLine(
    '签到开始',
    config?.signStartDate == null ? null : uiBykcDate(config!.signStartDate!),
  ),
  BykcInfoLine(
    '签到结束',
    config?.signEndDate == null ? null : uiBykcDate(config!.signEndDate!),
  ),
  BykcInfoLine(
    '签退开始',
    config?.signOutStartDate == null
        ? null
        : uiBykcDate(config!.signOutStartDate!),
  ),
  BykcInfoLine(
    '签退结束',
    config?.signOutEndDate == null ? null : uiBykcDate(config!.signOutEndDate!),
  ),
  BykcInfoLine(
    '签到地点',
    config == null || config.signPointCount == 0
        ? null
        : '${config.signPointCount} 处',
  ),
];

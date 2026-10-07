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
  String audience(List<String> values) =>
      values.isEmpty ? '未提供' : values.join('、');
  return [
    const SizedBox(height: 12),
    BykcSection('课程简介', [Text(supplement.descriptionPlainText ?? '未提供')]),
    const SizedBox(height: 12),
    BykcSection('适用范围', [
      BykcInfoLine('校区', audience(course.audienceCampuses)),
      BykcInfoLine('学院', audience(supplement.audienceColleges)),
      BykcInfoLine('年级', audience(supplement.audienceTerms)),
      BykcInfoLine('人群', audience(supplement.audienceGroups)),
    ]),
  ];
}

List<Widget> uiBykcDisplaySignFields(BykcSignDisplayConfig? config) => [
  BykcInfoLine(
    '签到开始',
    config?.signStartDate == null ? '未提供' : uiBykcDate(config!.signStartDate!),
  ),
  BykcInfoLine(
    '签到结束',
    config?.signEndDate == null ? '未提供' : uiBykcDate(config!.signEndDate!),
  ),
  BykcInfoLine(
    '签退开始',
    config?.signOutStartDate == null
        ? '未提供'
        : uiBykcDate(config!.signOutStartDate!),
  ),
  BykcInfoLine(
    '签退结束',
    config?.signOutEndDate == null
        ? '未提供'
        : uiBykcDate(config!.signOutEndDate!),
  ),
  BykcInfoLine('签到地点', config == null ? '未提供' : '${config.signPointCount} 处'),
];

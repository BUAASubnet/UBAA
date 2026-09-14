part of '../../widgets.dart';

List<Widget> _bykcContactFields(BykcCourseSupplement? supplement) => [
  _BykcInfoLine('联系人', supplement?.courseContact),
  _BykcInfoLine('联系电话', supplement?.courseContactMobile),
  _BykcInfoLine('开课单位', supplement?.organizerCollegeName),
];

List<Widget> _bykcSupplementSections(BykcCoursePresentation course) {
  final supplement = course.supplement;
  if (supplement == null) return const [];
  String audience(List<String> values) =>
      values.isEmpty ? '未提供' : values.join('、');
  return [
    const SizedBox(height: 12),
    _BykcSection('课程简介', [Text(supplement.descriptionPlainText ?? '未提供')]),
    const SizedBox(height: 12),
    _BykcSection('适用范围', [
      _BykcInfoLine('校区', audience(course.audienceCampuses)),
      _BykcInfoLine('学院', audience(supplement.audienceColleges)),
      _BykcInfoLine('年级', audience(supplement.audienceTerms)),
      _BykcInfoLine('人群', audience(supplement.audienceGroups)),
    ]),
  ];
}

List<Widget> _bykcDisplaySignFields(BykcSignDisplayConfig? config) => [
  _BykcInfoLine(
    '签到开始',
    config?.signStartDate == null ? '未提供' : _bykcDate(config!.signStartDate!),
  ),
  _BykcInfoLine(
    '签到结束',
    config?.signEndDate == null ? '未提供' : _bykcDate(config!.signEndDate!),
  ),
  _BykcInfoLine(
    '签退开始',
    config?.signOutStartDate == null
        ? '未提供'
        : _bykcDate(config!.signOutStartDate!),
  ),
  _BykcInfoLine(
    '签退结束',
    config?.signOutEndDate == null ? '未提供' : _bykcDate(config!.signOutEndDate!),
  ),
  _BykcInfoLine('签到地点', config == null ? '未提供' : '${config.signPointCount} 处'),
];

part of '../flow_test.dart';

/// 课表顶栏选择学期；换学期后课表重新定位该学期本周。
Future<void> _selectAcademicTerm(WidgetTester tester, String term) async {
  await _tapAcademic(tester, find.byTooltip('选择学期'));
  expect(find.byType(AlertDialog), findsOneWidget);
  await _tapAcademic(tester, find.widgetWithText(ListTile, term));
  expect(find.byType(AlertDialog), findsNothing);
}

Future<void> _checkAcademicDetails(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  Brightness brightness,
  FeatureId feature,
) async {
  final before = _academicSnapshot(tester, feature);
  expect(before.details, isNotEmpty);
  final detail = before.details.first;
  final title = find.text(detail.title).first;
  await _tapAcademic(tester, title);
  final dialog = find.byType(AlertDialog);
  expect(dialog, findsOneWidget);
  expect(
    find.descendant(of: dialog, matching: find.text(detail.title)),
    findsWidgets,
  );
  expect(_academicSnapshot(tester, feature), same(before));
  await _academicCapture(
    binding,
    tester,
    brightness,
    'normal-${feature.name}-local-detail',
    feature,
    '点击当前课程卡片查看本地详细信息，读取修订保持不变',
  );
  await _tapAcademic(tester, find.widgetWithText(TextButton, '关闭'));
  expect(
    _academicSnapshot(tester, feature).readContext!.requestRevision,
    before.readContext!.requestRevision,
  );
}

/// 校区与日期在宽屏正文切换；窄屏正文不提供这两项，只核对默认读取。
Future<void> _selectClassroomInputs(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  Brightness brightness,
) async {
  final campus = find.widgetWithText(SegmentedButton<int>, '沙河');
  if (campus.evaluate().isEmpty) {
    expect(
      _academicSnapshot(tester, FeatureId.classroom).status,
      FeatureLoadStatus.success,
    );
    return;
  }
  final before = _academicSnapshot(tester, FeatureId.classroom);
  final dateButton = find.ancestor(
    of: find.byIcon(Icons.date_range),
    matching: find.byType(OutlinedButton),
  );
  await _tapAcademic(tester, dateButton);
  expect(find.text('选择查询日期'), findsOneWidget);
  await _tapAcademic(tester, find.text('9').last);
  await _academicCapture(
    binding,
    tester,
    brightness,
    'normal-classroom-date-picker',
    FeatureId.classroom,
    '实际中文日期弹窗选择9日',
  );
  await _tapAcademic(tester, find.text('确定'));
  final dated = _academicSnapshot(tester, FeatureId.classroom);
  expect(
    dated.readContext!.requestRevision,
    greaterThan(before.readContext?.requestRevision ?? -1),
  );
  final day = dated.readContext!.query!.date!;
  expect(day.day, 9);
  await _tapAcademic(tester, campus);
  final all = _academicSnapshot(tester, FeatureId.classroom);
  final query = all.readContext!.query!;
  expect(query.floorId, isNull);
  expect(query.section, isNull);
  expect(query.date, day);
  expect(query.campus, 2);
  final rooms = all.details
      .map((detail) => detail.presentation! as ClassroomPresentation)
      .toList();
  expect(rooms, isNotEmpty);
  expect(rooms.every((room) => room.campus == 2), isTrue);
}

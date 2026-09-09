part of '../ui_academic_test.dart';

Future<void> _selectAcademicTerm(WidgetTester tester, FeatureId feature) async {
  final before = _academicSnapshot(tester, feature);
  await _tapAcademic(tester, find.text('选择学期'));
  expect(find.byType(AlertDialog), findsOneWidget);
  final option = find.widgetWithText(ListTile, '2026-2027-1');
  await _tapAcademic(tester, option);
  expect(find.byType(AlertDialog), findsNothing);
  expect(_academicFieldText(tester, '学期编码（可选）'), '2026-2027-1');
  expect(_academicSnapshot(tester, feature), same(before));
  expect(
    _academicSnapshot(tester, feature).readContext?.requestRevision,
    before.readContext?.requestRevision,
  );
}

Future<void> _checkAcademicTable(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  Brightness brightness,
  FeatureId feature,
) async {
  if (find.byType(DataTable).evaluate().isEmpty) {
    expect(
      tester.view.physicalSize.width / tester.view.devicePixelRatio,
      lessThan(768),
      reason: '本轮原生平板正常数据必须实际展示主要列',
    );
    return;
  }
  final tables = find.byType(DataTable);
  final table = tables.first;
  final labels = feature == FeatureId.grades
      ? ['课程（详情）', '成绩', '绩点', '学分']
      : ['课程（详情）', '日期 / 时间', '地点', '座位'];
  final physical = tester.view.physicalSize;
  final width = physical.width / tester.view.devicePixelRatio;
  final before = _academicSnapshot(tester, feature);
  for (var index = 0; index < tables.evaluate().length; index++) {
    final current = tables.at(index);
    for (final label in labels) {
      final column = find.descendant(of: current, matching: find.text(label));
      expect(column, findsOneWidget);
      final rect = tester.getRect(column);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(width));
    }
    expect(
      find.descendant(
        of: current,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      ),
      findsNothing,
    );
  }
  final title = before.details.first.title;
  await _tapAcademic(
    tester,
    find.descendant(of: table, matching: find.text(title)),
  );
  expect(find.text('详细信息'), findsOneWidget);
  expect(_academicSnapshot(tester, feature), same(before));
  await _academicCapture(
    binding,
    tester,
    brightness,
    'normal-${feature.name}-local-detail',
    feature,
    '原生宽表主要列均在真实视口内，点击课程查看本地更多字段，snapshot修订未变',
  );
  await _tapAcademic(tester, find.widgetWithText(TextButton, '关闭'));
  expect(
    _academicSnapshot(tester, feature).readContext!.requestRevision,
    before.readContext!.requestRevision,
  );
}

Future<void> _selectClassroomInputs(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  Brightness brightness,
) async {
  await _academicField(tester, '日期', '2026-09-08');
  final beforeDate = _academicSnapshot(tester, FeatureId.classroom);
  await _tapAcademic(tester, find.byTooltip('选择日期'));
  expect(find.text('选择查询日期'), findsOneWidget);
  expect(find.text('使用此日期'), findsOneWidget);
  expect(find.text('取消'), findsOneWidget);
  await _tapAcademic(tester, find.text('9').last);
  await _academicCapture(
    binding,
    tester,
    brightness,
    'normal-classroom-date-picker',
    FeatureId.classroom,
    '实际中文日期弹窗选择9日，未提交查询',
  );
  await _tapAcademic(tester, find.text('使用此日期'));
  expect(_academicFieldText(tester, '日期'), '2026-09-09');
  expect(_academicSnapshot(tester, FeatureId.classroom), same(beforeDate));
  await _academicField(tester, '楼层（可选）', '');
  await _academicField(tester, '节次（可选）', '');
  await _tapAcademic(tester, find.byType(DropdownButton<int>));
  await _tapAcademic(tester, find.text('沙河').last);
  await _applyAcademic(tester, FeatureId.classroom, FeatureQueryView.summary);
  final all = _academicSnapshot(tester, FeatureId.classroom);
  final query = all.readContext!.query!;
  expect(query.floorId, isNull);
  expect(query.section, isNull);
  expect(query.date, DateTime(2026, 9, 9));
  expect(query.campus, 2);
  final rooms = all.details
      .map((detail) => detail.presentation! as ClassroomPresentation)
      .toList();
  expect(
    rooms.every((room) => room.queryDate == '2026-09-09' && room.campus == 2),
    isTrue,
  );
  expect(rooms.any((room) => room.sectionTokens.contains('13')), isTrue);
  final chosen = rooms.firstWhere((room) => room.floorId == 'F03');
  if (find.text('当前页楼层').evaluate().isNotEmpty) {
    await _tapAcademic(tester, find.widgetWithText(ListTile, chosen.floorName));
    expect(_academicSnapshot(tester, FeatureId.classroom), same(all));
    await _academicCapture(
      binding,
      tester,
      brightness,
      'normal-classroom-local-floor',
      FeatureId.classroom,
      '宽屏本地楼层导航不请求backend',
    );
    await _tapAcademic(tester, find.widgetWithText(ListTile, '全部（本页）'));
  }
  await _tapAcademic(tester, find.byTooltip('选择楼层'));
  await _tapAcademic(
    tester,
    find.widgetWithText(ListTile, '${chosen.floorName} · ${chosen.floorId}'),
  );
  await _tapAcademic(tester, find.byTooltip('选择节次'));
  expect(find.widgetWithText(ListTile, '第 13 节'), findsOneWidget);
  await _tapAcademic(tester, find.widgetWithText(ListTile, '第 3 节'));
  expect(_academicSnapshot(tester, FeatureId.classroom), same(all));
  await _applyAcademic(tester, FeatureId.classroom, FeatureQueryView.summary);
  final filtered = _academicSnapshot(tester, FeatureId.classroom);
  expect(filtered.readContext!.query!.floorId, 'F03');
  expect(filtered.readContext!.query!.section, '3');
  expect(filtered.readContext!.query!.date, DateTime(2026, 9, 9));
  expect(filtered.readContext!.query!.campus, 2);
  expect(filtered.details, hasLength(1));
  final room = filtered.details.single.presentation! as ClassroomPresentation;
  expect(room.sectionTokens, contains('3'));
  expect(room.sectionTokens, isNot(contains('13')));
  // 再移除楼层约束，单独证明第3节不会误命中另一楼层的第13节。
  await _academicField(tester, '楼层（可选）', '');
  await _applyAcademic(tester, FeatureId.classroom, FeatureQueryView.summary);
  final sectionOnly = _academicSnapshot(tester, FeatureId.classroom);
  expect(sectionOnly.readContext!.query!.floorId, isNull);
  expect(sectionOnly.readContext!.query!.section, '3');
  expect(sectionOnly.details, hasLength(1));
  expect(
    (sectionOnly.details.single.presentation! as ClassroomPresentation)
        .sectionTokens,
    isNot(contains('13')),
  );
}

Future<void> _captureAcademicDateField(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  Brightness brightness,
) async {
  final field = _academicFieldFinder('日期');
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  expect(_academicFieldText(tester, '日期'), '2026-09-08');
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  final scrollable = find.descendant(
    of: editable,
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsOneWidget);
  final position = tester.state<ScrollableState>(scrollable).position;
  expect(position.pixels, 0);
  expect(position.maxScrollExtent, 0, reason: '完整日期必须适合实际文本视口，不通过内部横移隐藏末位');
  await _academicCapture(
    binding,
    tester,
    brightness,
    'long-classroom-date-field',
    FeatureId.classroom,
    '1.3字体下真实日期输入框，内部横滚偏移和最大范围均0，完整日期原图复核',
  );
}

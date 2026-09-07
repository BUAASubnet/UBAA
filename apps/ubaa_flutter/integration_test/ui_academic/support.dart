part of '../ui_academic_test.dart';

FeatureSnapshot _academicSnapshot(WidgetTester tester, FeatureId feature) =>
    tester
        .widget<UbaaMainShell>(find.byType(UbaaMainShell))
        .snapshots[feature]!;

String _academicFieldText(WidgetTester tester, String label) =>
    tester.widget<TextField>(_academicFieldFinder(label)).controller!.text;

Finder _academicFieldFinder(String label) {
  final prefix = label.split('（').first;
  return find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        (widget.decoration?.labelText?.startsWith(prefix) ?? false),
  );
}

Future<void> _loginAcademic(
  WidgetTester tester,
  Brightness brightness,
  String state, {
  double scale = 1,
}) async {
  expect(Platform.isIOS, isTrue);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    KeyedSubtree(
      key: ValueKey('academic-${brightness.name}-$state'),
      child: createInspectionApp(state: state),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(UbaaLoginView), findsOneWidget);
  await tester.enterText(find.byType(TextField).at(0), '2020000000');
  await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
  await tester.pump();
  await _tapAcademic(tester, find.widgetWithText(FilledButton, '登录'));
  expect(find.byType(UbaaMainShell), findsOneWidget);
  for (final feature in _academicFeatures) {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (_academicSnapshot(tester, feature).status ==
            FeatureLoadStatus.loading &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      _academicSnapshot(tester, feature).status,
      isNot(FeatureLoadStatus.loading),
    );
  }
}

Future<void> _tapAcademic(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _academicField(
  WidgetTester tester,
  String label,
  String value,
) async {
  final field = _academicFieldFinder(label);
  expect(field, findsOneWidget);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _openAcademic(WidgetTester tester, FeatureId feature) async {
  final selected = find.byIcon(Icons.home);
  await _tapAcademic(
    tester,
    selected.evaluate().isEmpty ? find.byIcon(Icons.home_outlined) : selected,
  );
  final grid = find.byType(CustomScrollView);
  expect(grid, findsOneWidget);
  final scrollable = find.descendant(
    of: grid,
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsOneWidget);
  Finder card(FeatureId feature) => find.descendant(
    of: grid,
    matching: find.widgetWithText(Card, feature.title),
  );
  await tester.scrollUntilVisible(
    card(FeatureId.schedule),
    -220,
    scrollable: scrollable,
  );
  await tester.scrollUntilVisible(card(feature), 220, scrollable: scrollable);
  await _tapAcademic(tester, card(feature));
}

Future<void> _chooseAcademicView(WidgetTester tester, String label) async {
  await _tapAcademic(tester, find.byType(DropdownButton<FeatureQueryView>));
  await _tapAcademic(tester, find.text(label).last);
}

Future<void> _applyAcademic(
  WidgetTester tester,
  FeatureId feature,
  FeatureQueryView view, {
  String? term,
  FeatureLoadStatus status = FeatureLoadStatus.success,
}) async {
  await _tapAcademic(tester, find.widgetWithText(FilledButton, '应用筛选'));
  final snapshot = _academicSnapshot(tester, feature);
  expect(snapshot.status, status);
  expect(snapshot.readContext, isNotNull);
  expect(snapshot.readContext!.query, isNotNull);
  expect(snapshot.readContext!.query!.view, view);
  if (term != null) expect(snapshot.readContext!.query!.term, term);
}

void _expectAcademicQuery(
  WidgetTester tester,
  FeatureId feature,
  FeatureQuery query,
) {
  final snapshot = _academicSnapshot(tester, feature);
  expect(snapshot.status, FeatureLoadStatus.success);
  expect(snapshot.readContext, isNotNull);
  expect(
    snapshot.readContext!.hasSameQuery(query),
    isTrue,
    reason: '校验合成backend完成后App记录的typed读取归属，不以UI回调当真实上游请求',
  );
}

Future<void> _waitAcademicStatus(
  WidgetTester tester,
  FeatureId feature,
  FeatureLoadStatus status,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (_academicSnapshot(tester, feature).status == status) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('学业合成结果未进入预期状态：${feature.name}/${status.name}');
}

String _searchFor(FeatureId feature) => switch (feature) {
  FeatureId.schedule => '数据结构',
  FeatureId.exam => '线性代数',
  FeatureId.grades => '程序设计',
  FeatureId.classroom => 'A201',
  _ => throw StateError('非学业领域'),
};

Future<void> _horizontalAcademic(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  Brightness brightness,
  FeatureId feature,
  String scene,
) async {
  if (feature != FeatureId.schedule) return;
  final viewport = find.byWidgetPredicate(
    (widget) =>
        widget is SingleChildScrollView &&
        widget.scrollDirection == Axis.horizontal,
  );
  if (viewport.evaluate().isEmpty) return; // 手机单列不执行宽表横移。
  expect(viewport, findsOneWidget);
  final horizontal = find.descendant(
    of: viewport,
    matching: find.byType(Scrollable),
  );
  expect(horizontal, findsOneWidget);
  await tester.ensureVisible(horizontal);
  await tester.pumpAndSettle();
  await tester.drag(horizontal, const Offset(-480, 0));
  await tester.pumpAndSettle();
  expect(
    tester.state<ScrollableState>(horizontal).position.pixels,
    greaterThan(0),
  );
  await _academicCapture(
    binding,
    tester,
    brightness,
    scene,
    feature,
    '实际内容宽度启用周课表列后横向滚动；不修改窗口尺寸',
  );
}

Future<void> _academicCapture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  Brightness brightness,
  String scene,
  FeatureId feature,
  String steps, {
  bool settle = true,
}) async {
  if (settle) await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 200));
  expect(tester.takeException(), isNull);
  final size = tester.view.physicalSize;
  final ratio = tester.view.devicePixelRatio;
  final shellContext = tester.element(find.byType(UbaaMainShell));
  expect(Theme.of(shellContext).brightness, brightness);
  final snapshot = _academicSnapshot(tester, feature);
  final query = snapshot.readContext?.query;
  final name = '${brightness.name}-$scene';
  final records =
      (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
            'uiEvidence',
            () => <Object?>[],
          )
          as List;
  records.add(<String, Object?>{
    'name': name,
    'scene': scene,
    'feature': feature.name,
    'steps': steps,
    'backend': 'synthetic-inspection',
    'platform': Platform.operatingSystem,
    'system': Platform.operatingSystemVersion,
    'physicalWidth': size.width,
    'physicalHeight': size.height,
    'logicalWidth': size.width / ratio,
    'logicalHeight': size.height / ratio,
    'devicePixelRatio': ratio,
    'theme': brightness.name,
    'themeSource': 'test-platform-brightness-override',
    'textScale': MediaQuery.textScalerOf(shellContext).scale(14) / 14,
    'textScaleSource': 'test-platform-text-scale',
    'viewportSource': 'native-view-unmodified',
    'snapshotStatus': snapshot.status.name,
    'requestRevision': snapshot.readContext?.requestRevision,
    'queryKind': query == null
        ? 'default-load-feature'
        : 'explicit-feature-query',
    'queryView': query?.view.name,
    'queryTerm': query?.term,
    'queryWeek': query?.week,
    'queryDate': query?.date?.toIso8601String(),
    'queryCampus': query?.campus,
    'queryFloor': query?.floorId,
    'querySection': query?.section,
    'contextMeaning': 'latest-backend-read-not-restored-parent-ui-cache',
    'paginationSource': snapshot.pagination == null
        ? 'local-or-none'
        : 'backend-metadata',
    'dateUtc': DateTime.now().toUtc().toIso8601String(),
    'sourceSha': const String.fromEnvironment(
      'UBAA_UI_SOURCE_SHA',
      defaultValue: 'unrecorded',
    ),
  });
  await binding.takeScreenshot(name);
}

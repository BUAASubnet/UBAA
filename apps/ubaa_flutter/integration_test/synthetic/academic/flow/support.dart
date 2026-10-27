part of '../flow_test.dart';

FeatureSnapshot _academicSnapshot(WidgetTester tester, FeatureId feature) =>
    tester
        .widget<UbaaMainShell>(find.byType(UbaaMainShell))
        .snapshots[feature]!;

final _academicSearchField = find.byKey(
  const ValueKey<String>('feature-search-field'),
);

/// 课表顶栏刷新与其他列表的“刷新当前查询”共用同一刷新按钮。
final _academicRefresh = find.byWidgetPredicate(
  (widget) => widget is Tooltip && (widget.message?.startsWith('刷新') ?? false),
);

String _academicSearchText(WidgetTester tester) =>
    tester.widget<TextField>(_academicSearchField).controller!.text;

Future<void> _academicSearch(WidgetTester tester, String value) async {
  await _tapAcademic(tester, _academicSearchField);
  await tester.enterText(_academicSearchField, value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _loginAcademic(
  WidgetTester tester,
  Brightness brightness,
  String state, {
  double scale = 1,
  Set<FeatureId>? failingReads,
  Future<void> Function()? beforeRead,
}) async {
  expect(Platform.isIOS || Platform.isMacOS, isTrue);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    KeyedSubtree(
      key: ValueKey('academic-${brightness.name}-$state'),
      child: createInspectionApp(
        state: state,
        failingReads: failingReads,
        beforeRead: beforeRead,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(UbaaLoginView), findsOneWidget);
  await tester.enterText(find.byType(TextField).at(0), '2020000000');
  await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
  await tester.pump();
  await _tapAcademic(tester, find.widgetWithText(FilledButton, '登录'));
  await uiWaitFor(
    tester,
    () => find.byType(UbaaMainShell).evaluate().isNotEmpty,
    '合成登录完成后进入主界面',
  );
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

Future<void> _openAcademic(WidgetTester tester, FeatureId feature) async {
  // 先逐级返回分组页，再沿学业入口点开功能卡片。
  for (
    var attempt = 0;
    attempt < 6 && find.byTooltip('返回').hitTestable().evaluate().isNotEmpty;
    attempt++
  ) {
    await _tapAcademic(tester, find.byTooltip('返回').hitTestable());
  }
  await _tapAcademic(
    tester,
    uiDestinationFinder(tester, UiDestination.academic),
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

void _expectScheduleWeek(WidgetTester tester, String term, int week) {
  final snapshot = _academicSnapshot(tester, FeatureId.schedule);
  expect(snapshot.status, FeatureLoadStatus.success);
  final query = snapshot.readContext!.query!;
  expect(query.view, FeatureQueryView.scheduleWeek);
  expect(query.term, term);
  expect(query.week, week);
  expect(
    snapshot.details.every(
      (item) => item.presentation is ScheduleCoursePresentation,
    ),
    isTrue,
  );
}

Future<void> _openAcademicFilter(WidgetTester tester) async {
  if (find.byTooltip('关闭筛选').hitTestable().evaluate().isNotEmpty) return;
  await _tapAcademic(
    tester,
    find.byKey(const ValueKey<String>('feature-filter-button')),
  );
}

Future<void> _closeAcademicFilter(WidgetTester tester) async {
  final close = find.byTooltip('关闭筛选').hitTestable();
  if (close.evaluate().isNotEmpty) await _tapAcademic(tester, close);
}

/// 状态标签点选即发出派生视图查询；重复点选已选项不重新读取。
Future<void> _chooseAcademicStatus(
  WidgetTester tester,
  FeatureId feature,
  String label,
  FeatureQueryView view,
) async {
  await _openAcademicFilter(tester);
  await _tapAcademic(tester, find.widgetWithText(ChoiceChip, label));
  final snapshot = _academicSnapshot(tester, feature);
  expect(snapshot.status, FeatureLoadStatus.success);
  expect(snapshot.readContext!.query!.view, view);
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
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.right,
    ),
  );
  expect(horizontal, findsOneWidget);
  final position = tester.state<ScrollableState>(horizontal).position;
  if (position.maxScrollExtent == 0) {
    expect(position.pixels, 0);
    return; // 宽表已完整放入视口时无需横向滚动。
  }
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
  // macOS 原生窗口截图由独立巡检负责；这里只在 iOS 取图。
  if (Platform.isIOS) await binding.takeScreenshot(name);
}

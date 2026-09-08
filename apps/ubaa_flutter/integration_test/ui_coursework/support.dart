part of '../ui_coursework_test.dart';

FeatureSnapshot _snapshot(WidgetTester tester, FeatureId feature) => tester
    .widget<UbaaMainShell>(find.byType(UbaaMainShell))
    .snapshots[feature]!;
Future<CourseworkBackend> _login(
  WidgetTester tester,
  Brightness brightness,
  String state,
) async {
  expect(Platform.isIOS || Platform.isMacOS, isTrue);
  expect(tester.view.physicalSize.width, greaterThan(0));
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.textScaleFactorTestValue = state == 'long'
      ? 1.3
      : 1;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final backend = CourseworkBackend(state: state);
  await tester.pumpWidget(
    KeyedSubtree(
      key: ValueKey('${brightness.name}-$state'),
      child: UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), 'coursework-fixture');
  await tester.enterText(find.byType(TextField).at(1), 'synthetic-password');
  FocusManager.instance.primaryFocus?.unfocus();
  await _tap(tester, find.widgetWithText(FilledButton, '登录'));
  expect(find.byType(UbaaMainShell), findsOneWidget);
  return backend;
}

Future<void> _ensure(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scrollables = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: scrollables.last,
      maxScrolls: 60,
    );
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await _ensure(tester, finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _open(WidgetTester tester, FeatureId feature) async {
  final index = ordinaryFeatureIds.contains(feature) ? 1 : 2;
  while (find.byType(NavigationBar).evaluate().isEmpty &&
      find.byType(NavigationRail).evaluate().isEmpty) {
    await _tap(tester, find.byTooltip('返回'));
  }
  if (find.byType(NavigationBar).evaluate().isNotEmpty) {
    await _tap(tester, find.byType(NavigationDestination).at(index));
  } else {
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    final selected = rail.selectedIndex == index;
    await _tap(
      tester,
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byIcon(
          index == 1
              ? (selected ? Icons.apps : Icons.apps_outlined)
              : (selected ? Icons.auto_awesome : Icons.auto_awesome_outlined),
        ),
      ),
    );
  }
  await _tap(tester, find.widgetWithText(Card, feature.title));
  expect(find.byType(TextField), findsNothing);
}

Future<void> _panel(WidgetTester tester, bool open) async {
  final done = find.widgetWithText(TextButton, '完成');
  if (open && done.evaluate().isEmpty) {
    await _tap(tester, find.byTooltip('搜索与筛选'));
  } else if (!open && done.evaluate().isNotEmpty) {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tap(tester, done);
  }
}

Future<String> _searchDraft(WidgetTester tester) async {
  await _panel(tester, true);
  final value = tester
      .widget<TextField>(find.widgetWithText(TextField, '筛选详情'))
      .controller!
      .text;
  await _panel(tester, false);
  return value;
}

Future<void> _search(WidgetTester tester, String value) async {
  await _panel(tester, true);
  final field = find.widgetWithText(TextField, '筛选详情');
  await _tap(tester, field);
  await tester.enterText(field, value);
  await tester.pump();
  expect(tester.widget<TextField>(field).controller!.text, value);
  await _panel(tester, false);
  expect(find.byType(TextField), findsNothing);
}

Future<void> _view(WidgetTester tester, String label) async {
  await _panel(tester, true);
  await _tap(tester, find.byType(DropdownButton<FeatureQueryView>));
  await _tap(tester, find.text(label).last);
}

Future<void> _apply(
  WidgetTester tester,
  FeatureId feature,
  FeatureQuery query,
) async {
  await _panel(tester, true);
  await _tap(tester, find.widgetWithText(FilledButton, '应用筛选'));
  // 现有通用表单无条件保留隐藏时段默认值；只校准手动应用，不污染typed导航。
  _expectQuery(
    tester,
    feature,
    query.copyWith(startTime: '08:00', endTime: '22:00'),
  );
  await _panel(tester, false);
}

void _expectQuery(WidgetTester tester, FeatureId feature, FeatureQuery query) {
  final context = _snapshot(tester, feature).readContext!;
  expect(context.query, isNotNull);
  expect(context.query!.hasSameParameters(query), isTrue);
}

Future<void> _shot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
  FeatureId feature, {
  bool settle = true,
}) async {
  if (settle) await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final size = tester.view.physicalSize, ratio = tester.view.devicePixelRatio;
  final context = tester.element(find.byType(UbaaMainShell));
  final snapshot = _snapshot(tester, feature),
      query = _snapshot(tester, feature).readContext?.query;
  final records =
      (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
            'uiEvidence',
            () => <Object?>[],
          )
          as List;
  records.add(<String, Object?>{
    'name': name,
    'scene': name,
    'feature': feature.name,
    'backend': 'synthetic-coursework',
    'platform': Platform.operatingSystem,
    'system': Platform.operatingSystemVersion,
    'physicalWidth': size.width,
    'physicalHeight': size.height,
    'logicalWidth': size.width / ratio,
    'logicalHeight': size.height / ratio,
    'devicePixelRatio': ratio,
    'viewportSource': 'native-view-unmodified',
    'imageEvidence': Platform.isIOS
        ? 'native-plugin'
        : 'separate-cua-review-required',
    'theme': Theme.of(context).brightness.name,
    'themeMode': tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .themeMode
        ?.name,
    'textScale': MediaQuery.textScalerOf(context).scale(14) / 14,
    'snapshotStatus': snapshot.status.name,
    'requestRevision': snapshot.readContext?.requestRevision,
    'queryView': query?.view.name,
    'queryAssignmentId': query?.assignmentId,
    'queryCourseId': query?.courseId,
    'includeExpired': query?.includeExpired,
    'judgeKeys': [
      for (final key in query?.judgeKeys ?? <JudgeAssignmentQueryKey>[])
        {'courseId': key.courseId, 'assignmentId': key.assignmentId},
    ],
    'sourceSha': const String.fromEnvironment(
      'UBAA_UI_SOURCE_SHA',
      defaultValue: 'unrecorded',
    ),
  });
  if (Platform.isIOS) {
    await binding.takeScreenshot(name);
  } else {
    // SDK没有macOS截图插件；此处只记录原生交互断言，窗口另用CUA检查。
    debugPrint('macOS原生交互检查点：$name');
  }
}

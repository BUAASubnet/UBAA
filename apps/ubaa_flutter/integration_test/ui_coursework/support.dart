part of '../ui_coursework_test.dart';

FeatureSnapshot _snapshot(WidgetTester tester, FeatureId feature) => tester
    .widget<UbaaMainShell>(find.byType(UbaaMainShell))
    .snapshots[feature]!;
Future<CourseworkBackend> _login(
  WidgetTester tester,
  Brightness brightness,
  String state,
) async {
  expect(Platform.isIOS, isTrue);
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
  final home = find.byIcon(Icons.home_outlined);
  await _tap(
    tester,
    home.evaluate().isNotEmpty ? home : find.byIcon(Icons.home),
  );
  final card = find.widgetWithText(Card, feature.title);
  final scroll = find
      .descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(card, 220, scrollable: scroll);
  await _tap(tester, card);
}

Future<void> _search(WidgetTester tester, String value) async {
  final field = find.widgetWithText(TextField, '筛选详情');
  await _tap(tester, field);
  await tester.pump();
  String currentText() => tester.widget<TextField>(field).controller!.text;
  await tester.enterText(field, value);
  debugPrint('合成输入时序：目标=$value；enterText返回=${currentText()}');
  await tester.pump();
  debugPrint('合成输入时序：pump后=${currentText()}');
  expect(currentText(), value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  debugPrint('合成输入时序：失焦后=${currentText()}');
  expect(currentText(), value);
}

Future<void> _view(WidgetTester tester, String label) async {
  await _tap(tester, find.byType(DropdownButton<FeatureQueryView>));
  await _tap(tester, find.text(label).last);
}

Future<void> _apply(
  WidgetTester tester,
  FeatureId feature,
  FeatureQuery query,
) async {
  await _tap(tester, find.widgetWithText(FilledButton, '应用筛选'));
  // 现有通用表单无条件保留隐藏时段默认值；只校准手动应用，不污染typed导航。
  _expectQuery(
    tester,
    feature,
    query.copyWith(startTime: '08:00', endTime: '22:00'),
  );
}

void _expectQuery(WidgetTester tester, FeatureId feature, FeatureQuery query) {
  final context = _snapshot(tester, feature).readContext!;
  expect(context.query, isNotNull);
  expect(context.query!.hasSameParameters(query), isTrue);
}

Finder _detailButton(String course) => find.descendant(
  of: find.widgetWithText(Card, course),
  matching: find.widgetWithText(FilledButton, '查看作业详情'),
);
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
  await binding.takeScreenshot(name);
}

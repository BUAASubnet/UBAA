part of 'flow_test.dart';

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
  final index = UiDestination.forFeature(feature).index;
  if (find.byType(NavigationBar).evaluate().isNotEmpty) {
    await _tap(tester, find.byType(NavigationDestination).at(index));
  } else {
    final destination = UiDestination.forFeature(feature);
    final selected = find.byIcon(destination.selectedIcon);
    final target = selected.evaluate().isNotEmpty
        ? selected
        : find.byIcon(destination.icon);
    await _tap(tester, target.first);
  }
  await _tap(tester, find.widgetWithText(Card, feature.title));
  expect(find.byType(TextField), findsNothing);
}

Future<void> _panel(WidgetTester tester, bool open) async {
  final close = find.byTooltip('关闭筛选').hitTestable();
  final button = find.byKey(const ValueKey<String>('feature-filter-button'));
  if (open && close.evaluate().isEmpty) {
    if (button.hitTestable().evaluate().isNotEmpty) await _tap(tester, button);
  } else if (!open) {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    if (close.evaluate().isNotEmpty) await _tap(tester, close);
  }
}

final _searchField = find.byKey(const ValueKey<String>('feature-search-field'));

Future<String> _searchDraft(WidgetTester tester) async =>
    tester.widget<TextField>(_searchField).controller!.text;

Future<void> _search(WidgetTester tester, String value) async {
  await _panel(tester, false);
  await _tap(tester, _searchField);
  await tester.enterText(_searchField, value);
  await tester.pump();
  expect(tester.widget<TextField>(_searchField).controller!.text, value);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

/// 状态筛选点选即发出派生视图查询，无需再点“应用”。
Future<void> _view(WidgetTester tester, String label) async {
  await _panel(tester, true);
  await _tap(tester, find.widgetWithText(ChoiceChip, label));
}

Future<void> _apply(
  WidgetTester tester,
  FeatureId feature,
  FeatureQuery query,
) async {
  _expectQuery(tester, feature, query);
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

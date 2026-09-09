part of 'native_test.dart';

Future<void> ensure(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scroll = find
        .byElementPredicate(
          (e) =>
              e.widget is Scrollable &&
              (e.widget as Scrollable).axisDirection == AxisDirection.down &&
              e is StatefulElement &&
              (e.state as ScrollableState).position.viewportDimension > 100,
        )
        .hitTestable()
        .last;
    await tester.drag(scroll, const Offset(0, 30000));
    await tester.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        240,
        scrollable: scroll,
        maxScrolls: 80,
      );
    }
  }
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await ensure(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
  String steps,
) async {
  // 原生引擎提交下一帧后再截屏，避免统计与顶栏跨帧的过渡图误作终态。
  await tester.pump(const Duration(milliseconds: 250));
  expect(tester.takeException(), isNull);
  final size = tester.view.physicalSize, ratio = tester.view.devicePixelRatio;
  final records =
      (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
            'uiEvidence',
            () => <Object?>[],
          )
          as List;
  records.add({
    'name': name,
    'steps': steps,
    'backend': 'synthetic-schedule-old',
    'platform': Platform.operatingSystem,
    'system': Platform.operatingSystemVersion,
    'logicalWidth': size.width / ratio,
    'logicalHeight': size.height / ratio,
    'devicePixelRatio': ratio,
    'viewportSource': 'native-view-unmodified',
    'dateUtc': DateTime.now().toUtc().toIso8601String(),
    'sourceSha': const String.fromEnvironment('UBAA_UI_SOURCE_SHA'),
  });
  if (Platform.isIOS) {
    await binding.takeScreenshot(name);
  } else {
    debugPrint('原生周课表检查点：$name');
  }
}

Future<void> edit(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextField, label);
  await tap(tester, field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
  expect(tester.widget<TextField>(field).controller!.text, text);
}

Future<void> mount(
  WidgetTester tester,
  ScheduleOldBackend backend,
  Brightness brightness, {
  double textScale = 1,
}) async {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  // 仅覆盖系统文字缩放，不改原生窗口尺寸。
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await tester.pumpWidget(
    UbaaFlutterApp(
      backend: backend,
      credentialVault: MemoryCredentialVault(),
      initialTab: 1,
    ),
  );
  await tester.pumpAndSettle();
  await tap(tester, find.widgetWithText(Card, FeatureId.schedule.title));
  await tap(tester, find.byTooltip('搜索与筛选'));
  await tap(tester, find.text('今日课程').last);
  await tap(tester, find.text('周课表').last);
  await edit(tester, '学期编码', '2026-2027-1');
  await edit(tester, '周次', '4');
  await tap(tester, find.widgetWithText(FilledButton, '应用筛选'));
  await tap(tester, find.widgetWithText(TextButton, '完成'));
  expect(find.byType(TextField), findsNothing);
  if (tester.view.physicalSize.width / tester.view.devicePixelRatio < 600) {
    expect(find.byType(NavigationBar), findsNothing);
  }
}

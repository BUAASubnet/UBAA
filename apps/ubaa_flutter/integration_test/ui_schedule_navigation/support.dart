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
    'backend': 'synthetic-schedule-navigation',
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
    debugPrint('原生周次导航检查点：$name');
    if (const bool.fromEnvironment('UBAA_UI_MACOS_CAPTURE')) {
      const directory = String.fromEnvironment('UBAA_UI_MACOS_CAPTURE_DIR');
      if (!directory.startsWith('/') ||
          !directory.contains('UBAA-ui-evidence-e3c-macos-')) {
        throw StateError('必须使用本批独立合成证据目录');
      }
      // 仅合成原生测试检查点：外部只读截窗完成后应答，不用于生产会话。
      await tester.runAsync(() async {
        final marker = File('$directory/pending');
        await marker.writeAsString(name, flush: true);
        final limit = DateTime.now().add(const Duration(seconds: 45));
        while (await marker.exists()) {
          if (DateTime.now().isAfter(limit)) {
            throw StateError('原生窗口截图未及时完成');
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
    }
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
  ScheduleNavigationBackend backend,
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
  expect(find.byType(TextField), findsNothing);
  if (tester.view.physicalSize.width / tester.view.devicePixelRatio < 600) {
    expect(find.byType(NavigationBar), findsNothing);
  }
}

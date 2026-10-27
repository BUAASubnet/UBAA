part of '../parity_test.dart';

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
  await tester.ensureVisible(finder);
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
    'backend': 'synthetic-classroom-old',
    'platform': Platform.operatingSystem,
    'system': Platform.operatingSystemVersion,
    'logicalWidth': size.width / ratio,
    'logicalHeight': size.height / ratio,
    'devicePixelRatio': ratio,
    'viewportSource': 'native-view-unmodified',
    'dateUtc': DateTime.now().toUtc().toIso8601String(),
    'sourceSha': const String.fromEnvironment('UBAA_UI_SOURCE_SHA'),
    if (Platform.isMacOS) 'imageSource': 'native-flutter-repaint-boundary',
  });
  if (Platform.isMacOS) {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('classroom-capture')),
    );
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final renders =
        binding.reportData!.putIfAbsent('nativeRenders', () => <Object?>[])
            as List;
    renders.add({'name': name, 'bytes': data!.buffer.asUint8List()});
  } else if (Platform.isIOS) {
    await binding.takeScreenshot(name);
  } else {
    debugPrint('原生教室表格检查点：$name');
  }
}

Future<void> mount(
  WidgetTester tester,
  ClassroomOldBackend backend,
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
    RepaintBoundary(
      key: const ValueKey('classroom-capture'),
      child: UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
        initialDestination: UiDestination.academic,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tap(tester, find.widgetWithText(Card, FeatureId.classroom.title));
  if (tester.view.physicalSize.width / tester.view.devicePixelRatio < 600) {
    expect(find.byType(NavigationBar), findsOneWidget);
  }
}

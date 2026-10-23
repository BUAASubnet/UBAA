part of '../navigation_test.dart';

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
  String steps,
) async {
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
    'imageSource': Platform.isMacOS
        ? 'native-flutter-repaint-boundary'
        : 'native-screenshot',
  });
  if (Platform.isMacOS) {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('schedule-capture')),
    );
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final renders =
        binding.reportData!.putIfAbsent('nativeRenders', () => <Object?>[])
            as List;
    renders.add({'name': name, 'bytes': data!.buffer.asUint8List()});
  } else {
    await binding.takeScreenshot(name);
  }
}

Future<void> mount(
  WidgetTester tester,
  ScheduleNavigationBackend backend,
  Brightness brightness, {
  double textScale = 1,
}) async {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    KeyedSubtree(
      key: UniqueKey(),
      child: RepaintBoundary(
        key: const ValueKey('schedule-capture'),
        child: UbaaFlutterApp(
          backend: backend,
          credentialVault: MemoryCredentialVault(),
          initialDestination: UiDestination.academic,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (Platform.isAndroid) {
    await IntegrationTestWidgetsFlutterBinding.instance
        .convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
  }
  await tap(tester, find.widgetWithText(Card, FeatureId.schedule.title));
}

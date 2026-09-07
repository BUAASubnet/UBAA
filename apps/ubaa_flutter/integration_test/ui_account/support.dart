part of '../ui_account_test.dart';

Future<void> _mountAccount(
  WidgetTester tester,
  UbaaBackend backend,
  CredentialVault vault,
  Brightness brightness, {
  double scale = 1,
}) async {
  expect(Platform.isIOS, isTrue);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    UbaaFlutterApp(backend: backend, credentialVault: vault),
  );
  await tester.pumpAndSettle();
}

Future<void> _loginAccount(
  WidgetTester tester, {
  bool remember = false,
  bool auto = false,
  bool succeeds = true,
}) async {
  await tester.enterText(find.byType(TextField).at(0), 'account-fixture');
  await tester.enterText(find.byType(TextField).at(1), 'synthetic-password');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final boxes = find.byType(Checkbox);
  // 先关闭自动登录，避免它反向强制打开“记住密码”。
  if (!auto && tester.widget<Checkbox>(boxes.at(1)).value!) {
    await _accountTap(tester, boxes.at(1));
  }
  if (tester.widget<Checkbox>(boxes.at(0)).value != remember) {
    await _accountTap(tester, boxes.at(0));
  }
  if (tester.widget<Checkbox>(boxes.at(1)).value != auto) {
    await _accountTap(tester, boxes.at(1));
  }
  await _accountTap(tester, find.widgetWithText(FilledButton, '登录'));
  expect(find.byType(UbaaMainShell), succeeds ? findsOneWidget : findsNothing);
}

Future<void> _accountTap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scrollables = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    expect(scrollables, findsOneWidget);
    await tester.scrollUntilVisible(finder, 220, scrollable: scrollables);
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _accountShot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final size = tester.view.physicalSize;
  final ratio = tester.view.devicePixelRatio;
  final visiblePage = find.byType(UbaaMainShell).evaluate().isNotEmpty
      ? find.byType(UbaaMainShell)
      : find.byType(UbaaLoginView);
  final context = tester.element(visiblePage);
  final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
  final records =
      (binding.reportData ??= <String, dynamic>{}).putIfAbsent(
            'uiEvidence',
            () => <Object?>[],
          )
          as List;
  records.add(<String, Object?>{
    'name': name,
    'scene': name,
    'backend': 'synthetic-account-fixture',
    'platform': Platform.operatingSystem,
    'system': Platform.operatingSystemVersion,
    'physicalWidth': size.width,
    'physicalHeight': size.height,
    'logicalWidth': size.width / ratio,
    'logicalHeight': size.height / ratio,
    'devicePixelRatio': ratio,
    'viewportSource': 'native-view-unmodified',
    'theme': Theme.of(context).brightness.name,
    'textScale': MediaQuery.textScalerOf(context).scale(14) / 14,
    'themeMode': materialApp.themeMode?.name,
    'themeSource': 'explicit-test-system-or-user-preference',
    'textScaleSource': 'test-platform-text-scale',
    'sourceSha': const String.fromEnvironment(
      'UBAA_UI_SOURCE_SHA',
      defaultValue: 'unrecorded',
    ),
    'dateUtc': DateTime.now().toUtc().toIso8601String(),
  });
  await binding.takeScreenshot(name);
}

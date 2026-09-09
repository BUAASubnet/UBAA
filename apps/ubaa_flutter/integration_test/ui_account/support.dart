part of '../ui_account_test.dart';

Future<void> _mountAccount(
  WidgetTester tester,
  UbaaBackend backend,
  CredentialVault vault,
  Brightness brightness, {
  double scale = 1,
}) async {
  expect(Platform.isIOS || Platform.isMacOS, isTrue);
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
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _accountShot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name, {
  bool pending = false,
}) async {
  if (pending) {
    await tester.pump(const Duration(milliseconds: 250));
  } else {
    await tester.pumpAndSettle();
  }
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
  if (Platform.isIOS) {
    await binding.takeScreenshot(name);
  } else {
    debugPrint('原生账号检查点：$name');
    const checkpoints = {
      'login-light-normal-initial',
      'login-light-normal-route',
      'login-light-normal-input',
      'login-light-pending',
      'normal-dark-masked',
      'long-dark-masked',
      'normal-light-settings',
      'normal-light-clear-confirm',
      'normal-light-diagnostics',
    };
    if (const bool.fromEnvironment('UBAA_ACCOUNT_MACOS_CAPTURE') &&
        checkpoints.contains(name)) {
      const directory = String.fromEnvironment(
        'UBAA_ACCOUNT_MACOS_CAPTURE_DIR',
      );
      if (!directory.startsWith('/') ||
          !directory.contains('UBAA-ui-evidence-e4-macos-')) {
        throw StateError('必须使用本批独立合成证据目录');
      }
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

Future<void> _accountBack(WidgetTester tester) async {
  await _accountTap(tester, find.byTooltip('返回'));
}

Future<void> _openAccountUtility(WidgetTester tester, String title) async {
  if (find.byTooltip('返回').evaluate().isNotEmpty) await _accountBack(tester);
  await _accountTap(tester, find.byIcon(Icons.menu));
  await _accountTap(tester, find.text(title));
  expect(find.widgetWithText(AppBar, title), findsOneWidget);
  expect(find.byTooltip('返回'), findsOneWidget);
  if (tester.view.physicalSize.width / tester.view.devicePixelRatio < 600) {
    expect(find.byType(NavigationBar), findsNothing);
  }
}

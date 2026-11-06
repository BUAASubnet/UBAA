import 'package:ubaa_test_support/materials.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_test_support/recovery.dart' as offline;

void main() {
  for (final required in [true, false]) {
    testWidgets(
      required ? '所需路线静默尝试耗尽后显示人工验证' : 'Auto 已有可用路线时直接进入且不显示另一条路线验证码',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(950, 1300));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final backend = _InteractiveBackend()
          ..requiredRoute = required ? ConnectionMode.webvpn : null;
        final gate = Completer<LoginVerificationState>();
        backend.beginGate = gate;
        await tester.pumpWidget(
          UbaaAppHost(backend: backend, credentialVault: _Vault()),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, '学号'),
          'synthetic-account',
        );
        await tester.enterText(
          find.widgetWithText(TextField, '密码'),
          'synthetic-password',
        );
        await tester.pump();
        await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
        await tester.tap(find.widgetWithText(FilledButton, '登录'));
        await tester.pump();
        expect(backend.beginCalls, 1);
        expect(find.byKey(const ValueKey('captcha-dialog')), findsNothing);
        expect(
          tester.widget<UbaaLoginView>(find.byType(UbaaLoginView)).isLoading,
          isTrue,
        );
        gate.complete(backend.waiting());
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('captcha-dialog')),
          required ? findsOneWidget : findsNothing,
        );
        if (!required) expect(find.byType(UbaaMainShell), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('离线首页原位完成验证码保留导航并绑定可恢复账号', (tester) async {
    // 文件协调使用真实事件循环，避免 Widget FakeAsync 阻止文件 I/O 完成。
    await tester.runAsync(() async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final materials = syntheticMaterials(
        offline.MemoryMaterials(),
        tester: tester,
      );
      await materials.probe();
      final accounts = SecureLocalAccountStore(materials);
      final before = await accounts.retain(
        'synthetic-account',
        retainSession: true,
      );
      final originalKey = await accounts.cacheKey(before.account!);
      final vault = PlatformCredentialVault(
        store: MaterialCredentialStore(materials),
      );
      final backend = _InteractiveBackend();
      await tester.pumpWidget(
        UbaaAppHost(
          backend: backend,
          localAccountStore: accounts,
          credentialVault: vault,
        ),
      );
      await offline.pumpRecoveryUntil(
        tester,
        () => find.byTooltip('完成登录').evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey<String>('tab-校园')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('完成登录'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '密码'),
        'synthetic-password',
      );
      await tester.tap(find.text('记住密码'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await offline.pumpRecoveryUntil(
        tester,
        () =>
            find.byKey(const ValueKey('captcha-dialog')).evaluate().isNotEmpty,
      );
      expect(find.byType(UbaaMainShell), findsOneWidget);
      expect(backend.beginCalls, 1);
      expect(find.byKey(const ValueKey('captcha-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('captcha-answer-webvpn')),
        'synthetic-answer',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('captcha-submit')));
      await offline.pumpRecoveryUntil(
        tester,
        () => find.byType(UbaaLoginView).evaluate().isEmpty,
      );
      expect(find.byType(UbaaLoginView), findsNothing);
      expect(find.byType(UbaaMainShell), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        UiDestination.campus.index,
      );
      expect((await accounts.read())!.canRestore, isTrue);
      expect((await accounts.read())!.account!.username, 'synthetic-account');
      expect((await accounts.read())!.account!.id, before.account!.id);
      expect(await accounts.cacheKey(before.account!), originalKey);
      expect(
        (await accounts.read())!.generation,
        greaterThan(before.generation),
      );
      expect((await vault.read())!.username, 'synthetic-account');
      expect(backend.legacyCalls, 0);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('实际 Host 刷新先清答案，保留账号输入并遵守登录保存选项', (tester) async {
    final backend = _InteractiveBackend();
    final vault = _Vault();
    await _openWaiting(tester, backend, vault: vault, rememberPassword: false);
    await tester.enterText(
      find.byKey(const ValueKey('captcha-answer-webvpn')),
      'synthetic-old-answer',
    );
    final gate = Completer<LoginVerificationState>();
    backend.refreshGate = gate;
    await tester.tap(find.byKey(const ValueKey('captcha-image-webvpn')));
    await tester.pump();
    expect(_field(tester, 'captcha-answer-webvpn').controller!.text, isEmpty);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '学号'))
          .controller!
          .text,
      'synthetic-account',
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '密码'))
          .controller!
          .text,
      'synthetic-password',
    );
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isFalse);
    gate.complete(backend.waiting());
    await tester.pumpAndSettle();
    expect(backend.refreshes, <ConnectionMode>[ConnectionMode.webvpn]);
    await tester.enterText(
      find.byKey(const ValueKey('captcha-answer-webvpn')),
      'synthetic-new-answer',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('captcha-submit')));
    await tester.pumpAndSettle();
    expect(find.byType(UbaaMainShell), findsOneWidget);
    expect(backend.answers, <ConnectionMode, String>{
      ConnectionMode.webvpn: 'synthetic-new-answer',
    });
    expect(vault.writes, 0);
    expect(vault.clears, 1);
    expect(backend.legacyCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('图片加载失败仍要求验证且可点击重试，不提交空答案', (tester) async {
    final backend = _InteractiveBackend();
    await _openWaiting(tester, backend);
    backend.refreshGate = Completer<LoginVerificationState>();
    await tester.tap(find.byKey(const ValueKey('captcha-image-webvpn')));
    await tester.pump();
    backend.refreshGate!.completeError(
      const BackendException(UbaaErrorCode.networkError),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('captcha-dialog')), findsOneWidget);
    expect(find.text('图片暂不可用，点击刷新'), findsOneWidget);
    expect(_field(tester, 'captcha-answer-webvpn').enabled, isFalse);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('captcha-submit')))
          .onPressed,
      isNull,
    );
    expect(backend.answers, isEmpty);
    expect(backend.beginCalls, 1);
  });

  testWidgets('本地 120 秒到期撤下图片和答案并保留同路线刷新入口', (tester) async {
    final backend = _InteractiveBackend();
    await _openWaiting(tester, backend);
    await tester.enterText(
      find.byKey(const ValueKey('captcha-answer-webvpn')),
      'synthetic-expiring-answer',
    );
    final original = tester
        .widget<UbaaLoginView>(find.byType(UbaaLoginView))
        .verification!
        .forRoute(ConnectionMode.webvpn)!
        .frame!;
    await tester.pump(const Duration(seconds: 119));
    expect(
      _field(tester, 'captcha-answer-webvpn').controller!.text,
      'synthetic-expiring-answer',
    );
    await tester.pump(const Duration(seconds: 1));
    expect(original.isReleased, isTrue);
    expect(_field(tester, 'captcha-answer-webvpn').controller!.text, isEmpty);
    expect(_field(tester, 'captcha-answer-webvpn').enabled, isFalse);
    expect(find.text('图片暂不可用，点击刷新'), findsOneWidget);
    expect(backend.discards, contains(ConnectionMode.webvpn));
    expect(backend.refreshes, isEmpty);
  });

  for (final state in <AppLifecycleState>[
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets('$state 立即清材料，迟到刷新和恢复可见不自动登录', (tester) async {
      final backend = _InteractiveBackend();
      await _openWaiting(tester, backend);
      backend.refreshGate = Completer<LoginVerificationState>();
      await tester.tap(find.byKey(const ValueKey('captcha-image-webvpn')));
      await tester.pump();
      for (final transition in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        if (state != AppLifecycleState.hidden) AppLifecycleState.paused,
        if (state == AppLifecycleState.detached) AppLifecycleState.detached,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(transition);
        await tester.pump();
      }
      final late = backend.waiting();
      backend.refreshGate!.complete(late);
      await tester.pump();
      for (final transition in <AppLifecycleState>[
        if (state == AppLifecycleState.paused) AppLifecycleState.hidden,
        if (state != AppLifecycleState.detached) AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(transition);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('captcha-answer-webvpn')), findsNothing);
      expect(find.byKey(const ValueKey('captcha-image-webvpn')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '密码'))
            .controller!
            .text,
        isEmpty,
      );
      expect(late.forRoute(ConnectionMode.webvpn)!.frame!.isReleased, isTrue);
      expect(backend.cancelCalls, greaterThan(0));
      expect(backend.beginCalls, 1);
      expect(backend.answers, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('登录页面销毁释放当前像素并撤销交互', (tester) async {
    final backend = _InteractiveBackend();
    await _openWaiting(tester, backend);
    final frame = tester
        .widget<UbaaLoginView>(find.byType(UbaaLoginView))
        .verification!
        .forRoute(ConnectionMode.webvpn)!
        .frame!;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(frame.isReleased, isTrue);
    expect(backend.cancelCalls, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive 保留验证窗口，人工完成后保持 Auto 策略', (tester) async {
    final backend = _InteractiveBackend();
    await _openWaiting(tester, backend);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byKey(const ValueKey('captcha-dialog')), findsOneWidget);
    expect(backend.cancelCalls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.enterText(
      find.byKey(const ValueKey('captcha-answer-webvpn')),
      'synthetic-answer',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('captcha-submit')));
    await tester.pumpAndSettle();
    expect(find.byType(UbaaMainShell), findsOneWidget);
    expect(backend.pinChoices, <bool>[false]);
    expect(backend.beginCalls, 1);
    expect(backend.legacyCalls, 0);
  });
}

TextField _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey<String>(key)));

Future<void> _openWaiting(
  WidgetTester tester,
  _InteractiveBackend backend, {
  CredentialVault? vault,
  bool rememberPassword = true,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.binding.setSurfaceSize(const Size(950, 1300));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UbaaAppHost(
      backend: backend,
      credentialVault: vault ?? MemoryCredentialVault(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, '学号'),
    'synthetic-account',
  );
  await tester.enterText(
    find.widgetWithText(TextField, '密码'),
    'synthetic-password',
  );
  if (rememberPassword) await tester.tap(find.text('记住密码'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '登录'));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('captcha-dialog')), findsOneWidget);
}

class _Vault extends MemoryCredentialVault {
  int writes = 0;
  int clears = 0;
  @override
  Future<void> write(Credential value) async {
    writes++;
    await super.write(value);
  }

  @override
  Future<void> clear() async {
    clears++;
    await super.clear();
  }
}

class _InteractiveBackend
    implements UbaaBackend, RouteSettingsBackend, InteractiveLoginBackend {
  int beginCalls = 0;
  int legacyCalls = 0;
  int cancelCalls = 0;
  int revision = 0;
  final refreshes = <ConnectionMode>[];
  final discards = <ConnectionMode>[];
  Map<ConnectionMode, String> answers = <ConnectionMode, String>{};
  Completer<LoginVerificationState>? refreshGate;
  Completer<LoginVerificationState>? beginGate;
  bool rejectAutoContinue = false;
  ConnectionMode? requiredRoute = ConnectionMode.webvpn;
  final pinChoices = <bool>[];

  LoginVerificationState waiting() => LoginVerificationState(
    requiredRoute: requiredRoute,
    profile: const UserSummary(username: 'synthetic-account'),
    routes: <LoginRouteVerification>[
      const LoginRouteVerification(
        route: ConnectionMode.direct,
        status: LoginRouteVerificationStatus.ready,
      ),
      LoginRouteVerification(
        route: ConnectionMode.webvpn,
        status: LoginRouteVerificationStatus.captchaRequired,
        revision: ++revision,
        validFor: const Duration(seconds: 120),
        frame: CaptchaPixelFrame(
          width: 1,
          height: 1,
          rgba: Uint8List.fromList(<int>[17, 83, 149, 255]),
        ),
      ),
    ],
  );

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedOut;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic-account');
  @override
  Future<void> prepareLogin(RoutePolicy value) async {}
  @override
  Future<void> login(LoginInput input) async {
    legacyCalls++;
    throw const BackendException(UbaaErrorCode.upstreamChanged);
  }

  @override
  Future<void> logout() async {}
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();
  @override
  Future<BackendRouteSettings> routeSettings() async =>
      const BackendRouteSettings(
        defaultPolicy: RoutePolicy.auto,
        activeRoutes: <ConnectionMode>[],
      );
  @override
  Future<LoginVerificationState> beginInteractiveLogin(LoginInput input) async {
    beginCalls++;
    return beginGate?.future ?? Future.value(waiting());
  }

  @override
  Future<LoginVerificationState> submitInteractiveLogin(
    LoginInput input,
    Map<ConnectionMode, String> values,
  ) async {
    answers = values;
    return LoginVerificationState(
      profile: const UserSummary(username: 'synthetic-account'),
      routes: <LoginRouteVerification>[
        for (final route in ConnectionMode.values)
          LoginRouteVerification(
            route: route,
            status: LoginRouteVerificationStatus.ready,
          ),
      ],
    );
  }

  @override
  Future<LoginVerificationState> refreshInteractiveCaptcha(
    ConnectionMode route,
  ) async {
    refreshes.add(route);
    return refreshGate?.future ??
        Future<LoginVerificationState>.value(waiting());
  }

  @override
  Future<InteractiveLoginCompletion> continueInteractiveLogin(
    ConnectionMode route, {
    bool pinRoute = false,
  }) async {
    pinChoices.add(pinRoute);
    if (rejectAutoContinue && !pinRoute)
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    return InteractiveLoginCompletion(
      user: const UserSummary(username: 'synthetic-account'),
      settings: BackendRouteSettings(
        defaultPolicy: pinRoute
            ? (route == ConnectionMode.direct
                  ? RoutePolicy.direct
                  : RoutePolicy.webvpn)
            : RoutePolicy.auto,
        activeRoutes: answers.isEmpty
            ? <ConnectionMode>[ConnectionMode.direct]
            : ConnectionMode.values,
      ),
    );
  }

  @override
  void discardInteractiveCaptcha(ConnectionMode route) {
    discards.add(route);
  }

  @override
  void cancelInteractiveLogin() {
    cancelCalls++;
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../ubaa_app/test/offline/startup_test.dart' as offline;

void main() {
  testWidgets('离线首页原位完成验证码保留导航并绑定可恢复账号', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final materials = SecureMaterialStore(transport: offline.MemoryMaterials());
    await materials.probe();
    final accounts = SecureLocalAccountStore(materials);
    await accounts.retain('synthetic-account', retainSession: true);
    final backend = _InteractiveBackend();
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        localAccountStore: accounts,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('tab-高级功能')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成登录'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '密码'),
      'synthetic-password',
    );
    await tester.tap(find.text('记住密码'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.byType(UbaaMainShell), findsOneWidget);
    expect(backend.beginCalls, 1);
    expect(find.text('WebVPN 验证码'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('captcha-answer-webvpn')),
      'synthetic-answer',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.byType(UbaaLoginView), findsNothing);
    expect(find.byType(UbaaMainShell), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect((await accounts.read())!.canRestore, isTrue);
    expect((await accounts.read())!.account!.username, 'synthetic-account');
    expect(backend.legacyCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('实际 Host 刷新先清答案，保留输入并按当前选项完成保存', (tester) async {
    final backend = _InteractiveBackend();
    final vault = _Vault();
    await _openWaiting(tester, backend, vault: vault);
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
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
    gate.complete(backend.waiting());
    await tester.pumpAndSettle();
    expect(backend.refreshes, <ConnectionMode>[ConnectionMode.webvpn]);
    await tester.enterText(
      find.byKey(const ValueKey('captcha-answer-webvpn')),
      'synthetic-new-answer',
    );
    await tester.tap(find.text('记住密码'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
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
    expect(find.text('WebVPN 验证码'), findsOneWidget);
    expect(find.text('图片暂不可用，点击刷新'), findsOneWidget);
    expect(_field(tester, 'captcha-answer-webvpn').enabled, isFalse);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '登录'))
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

  testWidgets('inactive 保留仍可见的验证码，Auto 显式改用按钮走专用继续', (tester) async {
    final backend = _InteractiveBackend()..rejectAutoContinue = true;
    await _openWaiting(tester, backend);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('WebVPN 验证码'), findsOneWidget);
    expect(backend.cancelCalls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.tap(find.text('保持自动连接并继续'));
    await tester.pumpAndSettle();
    expect(find.byType(UbaaLoginView), findsOneWidget);
    expect(find.text('自动连接暂未就绪'), findsOneWidget);
    await tester.tap(find.text('改用直连并继续'));
    await tester.pumpAndSettle();
    expect(find.byType(UbaaMainShell), findsOneWidget);
    expect(backend.pinChoices, <bool>[false, true]);
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
  await tester.tap(find.text('记住密码'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '登录'));
  await tester.pumpAndSettle();
  expect(find.text('WebVPN 验证码'), findsOneWidget);
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
  bool rejectAutoContinue = false;
  final pinChoices = <bool>[];

  LoginVerificationState waiting() => LoginVerificationState(
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
    return waiting();
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

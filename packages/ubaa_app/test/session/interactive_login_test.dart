import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/recovery.dart' as recovery;

void main() {
  test('会话恢复验证码耗尽后原位交接人工，完成时保留保存凭据与 Auto', () async {
    final accounts = await recovery.savedAccounts();
    await accounts.retain('synthetic-account', retainSession: true);
    final vault = MemoryCredentialVault(
      initial: const Credential(
        username: 'synthetic-account',
        password: 'synthetic-password',
        autoLogin: true,
      ),
    );
    final backend = _RecoveryCaptchaBackend();
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
      credentialVault: vault,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(refreshHomeAfter: false);
    expect(controller.phase, AppPhase.home);
    expect(controller.loginVerification!.hasCaptcha, isTrue);
    expect(backend.resumes, 1);
    expect(backend.beginCalls, 0);
    expect(backend.requiredLogins, 1);
    expect((await vault.read())!.autoLogin, isTrue);
    controller.setCaptchaAnswer(ConnectionMode.webvpn, 'synthetic-answer');
    await controller.submitLogin(preserveHome: true);
    expect(controller.loginVerification, isNull);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
    expect(controller.loginForm.routePolicy, RoutePolicy.auto);
    expect((await vault.read())!.autoLogin, isTrue);
    expect(backend.requiredLogins, 1);
  });
  test('人工接管期间保持待登录，恢复收尾不覆盖接管错误', () async {
    final accounts = await recovery.savedAccounts();
    await accounts.retain('synthetic-account', retainSession: true);
    final backend = _RecoveryCaptchaBackend()
      ..manualResponse = Completer<LoginVerificationState>();
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: 'synthetic-account',
          password: 'synthetic-password',
          autoLogin: true,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final pending = controller.recoverSession(refreshHomeAfter: false);
    await backend.manualStarted.future;
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.needsLogin);
    expect(controller.phase, AppPhase.home);
    backend.manualResponse!.completeError(
      const BackendException(UbaaErrorCode.networkError),
    );
    await pending;
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.needsLogin);
    expect(controller.error?.code, UbaaErrorCode.networkError);
    expect(controller.loginVerification, isNull);
    expect(controller.loginForm.password, isEmpty);
  });
  test('明确WebVPN已就绪时进入首页，不要求另一条路线的验证码', () async {
    final backend = _WebVpnReadyBackend();
    final controller = await _controller(backend);
    addTearDown(controller.dispose);
    await controller.submitLogin();
    expect(controller.phase, AppPhase.home);
    expect(controller.loginForm.routePolicy, RoutePolicy.webvpn);
    expect(controller.activeRoutes, [ConnectionMode.webvpn]);
    expect(backend.continued, [(ConnectionMode.webvpn, false)]);
    expect(backend.submissions, 0);
    expect(backend.unneededFrame!.isReleased, isTrue);
  });

  test('Auto 有可用直连会话时直接进入首页并释放另一条路线验证码', () async {
    final backend = _AutoReadyBackend();
    final controller = await _controller(backend);
    addTearDown(controller.dispose);
    await controller.submitLogin();
    expect(controller.phase, AppPhase.home);
    expect(controller.loginVerification, isNull);
    expect(controller.loginForm.routePolicy, RoutePolicy.auto);
    expect(backend.continued, [(ConnectionMode.direct, false)]);
    expect(backend.submissions, 0);
    expect(backend.frame!.isReleased, isTrue);
  });

  test('待确认写意图存在时不发起手动验证码认证或丢弃原确认', () async {
    final backend = _InteractiveBackend()..restoredSignedIn = true;
    final controller = await _controller(backend);
    addTearDown(controller.dispose);
    final intent = WriteIntent(
      intentId: 'synthetic-pending',
      operation: WriteOperation.bykcSelectCourse,
      targetSummary: '合成课程',
      resolvedRoute: ConnectionMode.webvpn,
      warnings: const [],
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      requestDigest: 'synthetic-digest',
    );
    controller.writeCoordinator.setIntent(intent);
    await controller.submitLogin(preserveHome: true);
    expect(backend.beginCalls, 0);
    expect(controller.writeCoordinator.intent, same(intent));
  });

  test('原位验证码保留首页，等待期间不读取也不准备写入，成功后恢复', () async {
    final backend = _InteractiveBackend()..restoredSignedIn = true;
    final controller = await _controller(backend);
    addTearDown(controller.dispose);
    await Future<void>.delayed(Duration.zero);
    final phases = <AppPhase>[];
    controller.addListener(() => phases.add(controller.phase));
    await controller.submitLogin(preserveHome: true);
    expect(controller.phase, AppPhase.home);
    expect(controller.isLoggingIn, isFalse);
    final before = backend.readCalls;
    final pendingRead = controller.refreshHome(only: [FeatureId.exam]);
    await Future<void>.delayed(Duration.zero);
    expect(backend.readCalls, before);
    var prepared = false;
    await controller.writeCoordinator.prepare(() async {
      prepared = true;
      throw StateError('合成写入不应开始');
    });
    expect(prepared, isFalse);
    controller.setCaptchaAnswer(ConnectionMode.webvpn, 'synthetic-answer');
    await controller.submitLogin(preserveHome: true);
    await pendingRead;
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
    expect(controller.loginVerification, isNull);
    expect(phases, everyElement(AppPhase.home));
  });

  test('原位取消后保留首页且不能把旧展示当作写资格', () async {
    final backend = _InteractiveBackend()..restoredSignedIn = true;
    final controller = await _controller(backend);
    addTearDown(controller.dispose);
    await controller.submitLogin(preserveHome: true);
    final frame = controller.loginVerification!
        .forRoute(ConnectionMode.webvpn)!
        .frame!;
    controller.cancelLoginVerification();
    expect(controller.phase, AppPhase.home);
    expect(frame.isReleased, isTrue);
    expect(controller.loginForm.password, isEmpty);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.needsLogin);
    var prepared = false;
    await controller.writeCoordinator.prepare(() async {
      prepared = true;
      throw StateError('取消登录后不应准备写入');
    });
    expect(prepared, isFalse);
  });

  test('等待时取消记住，完成验证后不保存最初的旧选项', () async {
    final backend = _InteractiveBackend();
    final vault = _CountingVault();
    final controller = await _controller(backend, vault: vault);
    addTearDown(controller.dispose);
    controller.setAutoLogin(true);
    await controller.submitLogin();
    expect(backend.beginCalls, 1);
    expect(controller.phase, AppPhase.login);
    expect(controller.loginVerification!.hasCaptcha, isTrue);
    expect(controller.activeRoutes, <ConnectionMode>[ConnectionMode.direct]);
    expect(controller.loginForm.password, 'synthetic-password');

    controller.setRememberPassword(false);
    controller.setCaptchaAnswer(ConnectionMode.webvpn, 'synthetic-answer');
    await controller.submitLogin();

    expect(controller.phase, AppPhase.home);
    expect(vault.writes, 0);
    expect(vault.clears, 1);
    expect(controller.loginForm.autoLogin, isFalse);
    expect(controller.loginForm.password, isEmpty);
    expect(backend.submissions, 1);
    expect(backend.legacyLogins, 0);
  });

  test('只刷新挑战路线，立即清答案且保留账号密码选项', () async {
    final backend = _InteractiveBackend();
    final controller = await _controller(backend);
    addTearDown(controller.dispose);
    controller.setRememberPassword(true);
    await controller.submitLogin();
    controller.setCaptchaAnswer(ConnectionMode.webvpn, 'synthetic-old-answer');
    backend.refreshGate = Completer<LoginVerificationState>();
    final refresh = controller.refreshCaptcha(ConnectionMode.webvpn);
    expect(
      controller.loginVerification!.forRoute(ConnectionMode.webvpn)!.answer,
      isEmpty,
    );
    expect(
      controller.loginVerification!.forRoute(ConnectionMode.webvpn)!.frame,
      isNull,
    );
    expect(controller.loginForm.username, 'synthetic-account');
    expect(controller.loginForm.password, 'synthetic-password');
    expect(controller.loginForm.rememberPassword, isTrue);
    backend.refreshGate!.complete(_waiting(2));
    await refresh;
    expect(backend.refreshedRoutes, <ConnectionMode>[ConnectionMode.webvpn]);
    expect(
      controller.loginVerification!.forRoute(ConnectionMode.webvpn)!.revision,
      2,
    );
  });

  test('隐藏后迟到图片不能恢复，后台重建不会重放密码', () async {
    final backend = _InteractiveBackend();
    final controller = await _controller(backend);
    addTearDown(controller.dispose);
    await controller.submitLogin();
    backend.refreshGate = Completer<LoginVerificationState>();
    final pending = controller.refreshCaptcha(ConnectionMode.webvpn);
    controller.cancelLoginVerification();
    final late = _waiting(2);
    backend.refreshGate!.complete(late);
    await pending;
    expect(controller.loginVerification, isNull);
    expect(controller.loginForm.password, isEmpty);
    expect(backend.cancelCalls, greaterThan(0));
    expect(backend.submissions, 0);
    expect(late.forRoute(ConnectionMode.webvpn)!.frame!.isReleased, isTrue);
  });

  for (final editAccount in <bool>[false, true]) {
    test('等待时修改${editAccount ? '账号' : '密码'}撤销旧挑战且不保存旧凭据', () async {
      final backend = _InteractiveBackend();
      final vault = _CountingVault();
      final controller = await _controller(backend, vault: vault);
      addTearDown(controller.dispose);
      controller.setRememberPassword(true);
      await controller.submitLogin();
      final frame = controller.loginVerification!
          .forRoute(ConnectionMode.webvpn)!
          .frame!;
      if (editAccount) {
        controller.setUsername('synthetic-second-account');
      } else {
        controller.setPassword('synthetic-new-password');
      }
      expect(controller.loginVerification, isNull);
      expect(frame.isReleased, isTrue);
      expect(vault.writes, 0);
      expect(backend.cancelCalls, greaterThan(0));
      expect(
        controller.loginForm.password,
        editAccount ? '' : 'synthetic-new-password',
      );
    });
  }

  test('等待验证码后的 backend 重建保留手动登录要求，不恢复旧成功槽位', () async {
    final backend = _InteractiveBackend();
    final replacement = _InteractiveBackend()..restoredSignedIn = true;
    final controller = AppController(
      backend: backend,
      backendFactory: () => replacement,
      credentialVault: MemoryCredentialVault(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setUsername('synthetic-account');
    controller.setPassword('synthetic-password');
    await controller.submitLogin();
    expect(await controller.rebuildBackend(), isTrue);
    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect(controller.loginVerification, isNull);
    expect(controller.loginForm.password, isEmpty);
    expect(replacement.beginCalls, 0);
    expect(replacement.legacyLogins, 0);
    expect(backend.disposed, isTrue);
  });

  test('自动登录复用静默认证，需要人工输入时保留当前密码和保存的凭据', () async {
    final backend = _InteractiveBackend();
    final vault = MemoryCredentialVault(
      initial: const Credential(
        username: 'synthetic-account',
        password: 'synthetic-password',
        autoLogin: true,
      ),
    );
    final controller = AppController(backend: backend, credentialVault: vault);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(backend.legacyLogins, 0);
    expect(backend.beginCalls, 1);
    expect(controller.phase, AppPhase.login);
    expect(controller.loginForm.password, 'synthetic-password');
    expect(controller.loginVerification!.hasCaptcha, isTrue);
    expect((await vault.read())!.password, 'synthetic-password');
  });

  test('验证码提交途中退出后，迟到成功不能保存凭据或恢复页面', () async {
    final backend = _InteractiveBackend();
    final vault = _CountingVault();
    final controller = await _controller(backend, vault: vault);
    addTearDown(controller.dispose);
    controller.setRememberPassword(true);
    await controller.submitLogin();
    controller.setCaptchaAnswer(ConnectionMode.webvpn, 'synthetic-answer');
    backend.submitGate = Completer<LoginVerificationState>();
    final pending = controller.submitLogin();
    await controller.logout();
    backend.submitGate!.complete(_completed());
    await pending;
    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect(controller.activeRoutes, isEmpty);
    expect(controller.loginVerification, isNull);
    expect(vault.writes, 0);
  });

  test('Auto 普通继续失败保留交互，显式改用就绪路线后才固定策略', () async {
    final backend = _InteractiveBackend()..rejectAutoContinue = true;
    final controller = await _controller(backend);
    addTearDown(controller.dispose);
    await controller.submitLogin();
    await controller.continueReadyLogin(ConnectionMode.direct);
    expect(controller.phase, AppPhase.login);
    expect(controller.loginForm.routePolicy, RoutePolicy.auto);
    expect(controller.loginVerification!.readyRoutes, <ConnectionMode>[
      ConnectionMode.direct,
    ]);
    expect(controller.loginVerification!.profile, isNotNull);
    backend.failPinnedContinue = true;
    await controller.continueWithFixedReadyRoute(ConnectionMode.direct);
    expect(controller.phase, AppPhase.login);
    expect(controller.loginForm.routePolicy, RoutePolicy.auto);
    expect(controller.loginVerification, isNotNull);
    backend.failPinnedContinue = false;
    await controller.continueWithFixedReadyRoute(ConnectionMode.direct);
    expect(controller.phase, AppPhase.home);
    expect(controller.loginForm.routePolicy, RoutePolicy.direct);
    expect(backend.continued, <(ConnectionMode, bool)>[
      (ConnectionMode.direct, false),
      (ConnectionMode.direct, true),
      (ConnectionMode.direct, true),
    ]);
    expect(backend.beginCalls, 1);
    expect(backend.submissions, 0);
  });
}

Future<AppController> _controller(
  _InteractiveBackend backend, {
  CredentialVault? vault,
}) async {
  final controller = AppController(
    backend: backend,
    credentialVault: vault ?? MemoryCredentialVault(),
  );
  await controller.initialize();
  controller.setUsername('synthetic-account');
  controller.setPassword('synthetic-password');
  return controller;
}

LoginVerificationState _waiting(
  int revision, {
  ConnectionMode? requiredRoute = ConnectionMode.webvpn,
}) => LoginVerificationState(
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
      revision: revision,
      validFor: const Duration(seconds: 120),
      frame: CaptchaPixelFrame(
        width: 1,
        height: 1,
        rgba: Uint8List.fromList(<int>[17, 83, 149, 255]),
      ),
    ),
  ],
);

LoginVerificationState _completed() => LoginVerificationState(
  profile: const UserSummary(username: 'synthetic-account'),
  routes: <LoginRouteVerification>[
    for (final route in ConnectionMode.values)
      LoginRouteVerification(
        route: route,
        status: LoginRouteVerificationStatus.ready,
      ),
  ],
);

class _CountingVault extends MemoryCredentialVault {
  int writes = 0;
  int clears = 0;
  @override
  Future<void> write(Credential credential) async {
    writes++;
    await super.write(credential);
  }

  @override
  Future<void> clear() async {
    clears++;
    await super.clear();
  }
}

class _InteractiveBackend
    implements
        UbaaBackend,
        InteractiveLoginBackend,
        RouteSettingsBackend,
        BackendLifecycle {
  int beginCalls = 0;
  int readCalls = 0;
  int submissions = 0;
  int legacyLogins = 0;
  int cancelCalls = 0;
  final refreshedRoutes = <ConnectionMode>[];
  Completer<LoginVerificationState>? refreshGate;
  Completer<LoginVerificationState>? submitGate;
  bool restoredSignedIn = false;
  bool disposed = false;
  bool rejectAutoContinue = false;
  bool failPinnedContinue = false;
  final continued = <(ConnectionMode, bool)>[];

  @override
  Future<AuthStatus> authStatus() async =>
      restoredSignedIn ? AuthStatus.signedIn : AuthStatus.signedOut;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic-account');
  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}
  @override
  Future<void> login(LoginInput input) async {
    legacyLogins++;
    throw const BackendException(UbaaErrorCode.upstreamChanged);
  }

  @override
  Future<void> logout() async {}
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    readCalls++;
    return const FeatureResult.empty();
  }

  @override
  Future<BackendRouteSettings> routeSettings() async =>
      const BackendRouteSettings(
        defaultPolicy: RoutePolicy.auto,
        activeRoutes: <ConnectionMode>[],
      );
  @override
  Future<LoginVerificationState> beginInteractiveLogin(LoginInput input) async {
    beginCalls++;
    return _waiting(1);
  }

  @override
  Future<LoginVerificationState> submitInteractiveLogin(
    LoginInput input,
    Map<ConnectionMode, String> answers,
  ) async {
    submissions++;
    expect(answers, <ConnectionMode, String>{
      ConnectionMode.webvpn: 'synthetic-answer',
    });
    return submitGate?.future ??
        Future<LoginVerificationState>.value(_completed());
  }

  @override
  Future<LoginVerificationState> refreshInteractiveCaptcha(
    ConnectionMode route,
  ) async {
    refreshedRoutes.add(route);
    return refreshGate?.future ??
        Future<LoginVerificationState>.value(_waiting(2));
  }

  @override
  Future<InteractiveLoginCompletion> continueInteractiveLogin(
    ConnectionMode selectedRoute, {
    bool pinRoute = false,
  }) async {
    continued.add((selectedRoute, pinRoute));
    if (rejectAutoContinue && !pinRoute)
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    if (failPinnedContinue && pinRoute)
      throw const BackendException(UbaaErrorCode.internalError);
    return InteractiveLoginCompletion(
      user: const UserSummary(username: 'synthetic-account'),
      settings: BackendRouteSettings(
        defaultPolicy: pinRoute
            ? (selectedRoute == ConnectionMode.direct
                  ? RoutePolicy.direct
                  : RoutePolicy.webvpn)
            : RoutePolicy.auto,
        activeRoutes: submissions == 0
            ? <ConnectionMode>[ConnectionMode.direct]
            : ConnectionMode.values,
      ),
    );
  }

  @override
  void discardInteractiveCaptcha(ConnectionMode route) {}
  @override
  void cancelInteractiveLogin() {
    cancelCalls++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _WebVpnReadyBackend extends _InteractiveBackend {
  CaptchaPixelFrame? unneededFrame;
  @override
  Future<BackendRouteSettings> routeSettings() async =>
      const BackendRouteSettings(
        defaultPolicy: RoutePolicy.webvpn,
        activeRoutes: [],
      );
  @override
  Future<LoginVerificationState> beginInteractiveLogin(LoginInput input) async {
    beginCalls++;
    final frame = CaptchaPixelFrame(
      width: 1,
      height: 1,
      rgba: Uint8List.fromList([17, 83, 149, 255]),
    );
    unneededFrame = frame;
    return LoginVerificationState(
      routes: [
        LoginRouteVerification(
          route: ConnectionMode.direct,
          status: LoginRouteVerificationStatus.captchaRequired,
          revision: 1,
          frame: frame,
          validFor: const Duration(seconds: 120),
        ),
        const LoginRouteVerification(
          route: ConnectionMode.webvpn,
          status: LoginRouteVerificationStatus.ready,
        ),
      ],
    );
  }

  @override
  Future<InteractiveLoginCompletion> continueInteractiveLogin(
    ConnectionMode selectedRoute, {
    bool pinRoute = false,
  }) async {
    continued.add((selectedRoute, pinRoute));
    return const InteractiveLoginCompletion(
      user: UserSummary(username: 'synthetic-account'),
      settings: BackendRouteSettings(
        defaultPolicy: RoutePolicy.webvpn,
        activeRoutes: [ConnectionMode.webvpn],
      ),
    );
  }
}

class _RecoveryCaptchaBackend extends _InteractiveBackend
    implements RequiredSessionBackend, ManualCaptchaBackend {
  int resumes = 0, requiredLogins = 0;
  Completer<LoginVerificationState>? manualResponse;
  final manualStarted = Completer<void>();
  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    throw const BackendException(
      UbaaErrorCode.authenticationRequired,
      resolvedRoute: ConnectionMode.webvpn,
    );
  }

  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) async {
    requiredLogins++;
    throw const BackendException(
      UbaaErrorCode.authenticationRequired,
      captchaRequired: true,
      resolvedRoute: ConnectionMode.webvpn,
    );
  }

  @override
  Future<LoginVerificationState> resumeRequiredCaptcha(
    LoginInput input,
    ConnectionMode route,
  ) async {
    resumes++;
    expect(route, ConnectionMode.webvpn);
    expect(input.password, 'synthetic-password');
    if (manualResponse case final response?) {
      manualStarted.complete();
      return response.future;
    }
    final waiting = _waiting(1);
    return LoginVerificationState(
      routes: waiting.routes,
      profile: waiting.profile,
      requiredRoute: route,
    );
  }
}

class _AutoReadyBackend extends _InteractiveBackend {
  CaptchaPixelFrame? frame;
  @override
  Future<LoginVerificationState> beginInteractiveLogin(LoginInput input) async {
    beginCalls++;
    final state = _waiting(1, requiredRoute: null);
    frame = state.forRoute(ConnectionMode.webvpn)!.frame;
    return state;
  }
}

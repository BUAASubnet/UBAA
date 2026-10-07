import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  for (final finishing in ['拒绝身份', '保存账号']) {
    test('$finishing的迟到错误不能覆盖退出后的新表单', () async {
      final gate = Completer<void>(), started = Completer<void>();
      final accounts = ProbeAccounts()
        ..firstSignOut = finishing == '拒绝身份' ? gate : null
        ..retainGate = finishing == '保存账号' ? gate : null
        ..storageStarted = started;
      final backend = InteractiveProbeBackend()
        ..profile = UserSummary(
          username: finishing == '拒绝身份' ? 'synthetic-b' : 'synthetic-a',
        );
      final c = AppController(backend: backend, localAccountStore: accounts);
      addTearDown(c.dispose);
      await c.initialize();
      c.setUsername('synthetic-a');
      c.setPassword('synthetic-password');
      final login = c.submitLogin();
      await started.future;
      await c.logout();
      c.setUsername('synthetic-c');
      c.setPassword('synthetic-new-password');
      gate.completeError(const SecureMaterialException());
      await login;
      expect(c.phase, AppPhase.login);
      expect(c.user, isNull);
      expect(c.error, isNull);
      expect(c.isLoggingIn, isFalse);
      expect(c.loginForm.username, 'synthetic-c');
      expect(c.loginForm.password, 'synthetic-new-password');
    });
  }

  test('旧路线失败不能清空退出后显式取得的新路线状态', () async {
    final backend = ProbeBackend();
    final c = AppController(backend: backend);
    addTearDown(c.dispose);
    await c.initialize();
    c.setUsername('synthetic-a');
    c.setPassword('synthetic-password');
    backend.delayRoute = true;
    final login = c.submitLogin();
    await backend.routeStarted.future;
    await c.logout();
    backend.delayRoute = false;
    backend.settings = const BackendRouteSettings(
      defaultPolicy: RoutePolicy.direct,
      activeRoutes: [ConnectionMode.direct],
    );
    await c.setRoutePolicy(RoutePolicy.direct);
    backend.routeRelease.completeError(
      const BackendException(UbaaErrorCode.networkError),
    );
    await login;
    expect(c.activeRoutes, [ConnectionMode.direct]);
    expect(c.loginForm.routePolicy, RoutePolicy.direct);
    expect(c.error, isNull);
  });

  test('所需路线恢复的第二次快照晚于退出返回不能恢复路线', () async {
    final backend = RecoveryProbeBackend();
    final c = AppController(
      backend: backend,
      localAccountStore: ProbeAccounts(initial: true),
    );
    addTearDown(c.dispose);
    await c.initialize();
    final recovery = c.recoverSession(refreshHomeAfter: false);
    await backend.routeStarted.future;
    await c.logout();
    expect(c.activeRoutes, isEmpty);
    backend.routeRelease.complete(
      const BackendRouteSettings(
        defaultPolicy: RoutePolicy.webvpn,
        activeRoutes: [ConnectionMode.webvpn],
      ),
    );
    await recovery;
    expect(c.activeRoutes, isEmpty);
    expect(c.loginForm.routePolicy, RoutePolicy.auto);
  });

  test('交互登录身份不匹配必须回到可再次登录状态', () async {
    final backend = InteractiveProbeBackend()
      ..profile = const UserSummary(username: 'synthetic-b');
    final c = AppController(
      backend: backend,
      localAccountStore: ProbeAccounts(),
    );
    addTearDown(c.dispose);
    await c.initialize();
    c.setUsername('synthetic-a');
    c.setPassword('synthetic-password');
    await c.submitLogin();
    expect(c.error?.code, UbaaErrorCode.authenticationRequired);
    expect(c.activeRoutes, isEmpty);
    expect(c.phase, AppPhase.login);
    expect(c.isLoggingIn, isFalse);
  });
  test('原位换账号索引关闭失败必须显示错误并解除登录中', () async {
    final backend = InteractiveProbeBackend()
      ..profile = const UserSummary(username: 'synthetic-b');
    final c = AppController(
      backend: backend,
      localAccountStore: ProbeAccounts(initial: true, failSignOut: true),
    );
    addTearDown(c.dispose);
    await c.initialize();
    expect(c.phase, AppPhase.home);
    c.setUsername('synthetic-b');
    c.setPassword('synthetic-password');
    await c.submitLogin(preserveHome: true);
    expect(
      {'error': c.error, 'isLoggingIn': c.isLoggingIn},
      {'error': isNotNull, 'isLoggingIn': false},
    );
  });

  test('账号不匹配必须回到可再次登录状态', () async {
    final backend = ProbeBackend();
    final c = AppController(
      backend: backend,
      localAccountStore: ProbeAccounts(),
    );
    addTearDown(c.dispose);
    await c.initialize();
    c.setUsername('synthetic-a');
    c.setPassword('synthetic-password');
    backend.profile = const UserSummary(username: 'synthetic-b');
    await c.submitLogin();
    expect(c.error?.code, UbaaErrorCode.authenticationRequired);
    expect(c.activeRoutes, isEmpty);
    expect(c.user, isNull);
    expect(c.phase, AppPhase.login);
    expect(c.isLoggingIn, isFalse);
  });
  test('登录期间路线快照晚于退出返回不能恢复活动路线', () async {
    final backend = ProbeBackend();
    final c = AppController(backend: backend);
    addTearDown(c.dispose);
    await c.initialize();
    c.setUsername('synthetic-a');
    c.setPassword('synthetic-password');
    backend.delayRoute = true;
    final login = c.submitLogin();
    await backend.routeStarted.future;
    await c.logout();
    expect(c.activeRoutes, isEmpty);
    backend.routeRelease.complete(
      const BackendRouteSettings(
        defaultPolicy: RoutePolicy.webvpn,
        activeRoutes: [ConnectionMode.webvpn],
      ),
    );
    await login;
    expect(c.phase, AppPhase.login);
    expect(c.user, isNull);
    expect(c.activeRoutes, isEmpty);
    expect(c.loginForm.routePolicy, RoutePolicy.auto);
  });
}

class ProbeBackend implements UbaaBackend, RouteSettingsBackend {
  bool delayRoute = false;
  BackendRouteSettings settings = const BackendRouteSettings(
    defaultPolicy: RoutePolicy.auto,
    activeRoutes: [],
  );
  final routeStarted = Completer<void>();
  final routeRelease = Completer<BackendRouteSettings>();
  UserSummary? profile = const UserSummary(username: 'synthetic-a');
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedOut;
  @override
  Future<UserSummary?> userInfo() async => profile;
  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}
  @override
  Future<void> login(LoginInput input) async {}
  @override
  Future<void> logout() async {}
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();
  @override
  Future<BackendRouteSettings> routeSettings() async {
    if (delayRoute) {
      routeStarted.complete();
      return routeRelease.future;
    }
    return settings;
  }
}

class ProbeAccounts implements LocalAccountStore {
  ProbeAccounts({this.initial = false, this.failSignOut = false});
  final bool initial, failSignOut;
  Completer<void>? firstSignOut, retainGate, storageStarted;
  int signOutCalls = 0;
  @override
  Future<LocalAccountState?> read() async => initial
      ? const LocalAccountState(
          account: LocalAccount(
            id: 'synthetic-initial',
            username: 'synthetic-a',
          ),
          canRestore: true,
          generation: 0,
        )
      : null;
  @override
  Future<LocalAccountState> retain(
    String username, {
    required bool retainSession,
  }) async {
    if (retainGate != null) {
      storageStarted!.complete();
      await retainGate!.future;
    }
    return LocalAccountState(
      account: LocalAccount(id: 'synthetic-account', username: username),
      canRestore: retainSession,
      generation: 1,
    );
  }

  @override
  Future<Uint8List> cacheKey(LocalAccount account) async => Uint8List(32);
  @override
  Future<void> signOut() async {
    if (++signOutCalls == 1 && firstSignOut != null) {
      storageStarted!.complete();
      await firstSignOut!.future;
    }
    if (failSignOut) throw const SecureMaterialException();
  }

  @override
  Future<void> removeAccount(String accountId) async {}
}

class InteractiveProbeBackend extends ProbeBackend
    implements InteractiveLoginBackend {
  @override
  Future<LoginVerificationState> beginInteractiveLogin(
    LoginInput input,
  ) async => LoginVerificationState(
    routes: [
      for (final route in ConnectionMode.values)
        LoginRouteVerification(
          route: route,
          status: LoginRouteVerificationStatus.ready,
        ),
    ],
    profile: profile,
  );
  @override
  Future<LoginVerificationState> submitInteractiveLogin(
    LoginInput input,
    Map<ConnectionMode, String> answers,
  ) => beginInteractiveLogin(input);
  @override
  Future<LoginVerificationState> refreshInteractiveCaptcha(
    ConnectionMode route,
  ) => throw UnimplementedError();
  @override
  Future<InteractiveLoginCompletion> continueInteractiveLogin(
    ConnectionMode selectedRoute, {
    bool pinRoute = false,
  }) async => InteractiveLoginCompletion(
    user: profile!,
    settings: const BackendRouteSettings(
      defaultPolicy: RoutePolicy.auto,
      activeRoutes: ConnectionMode.values,
    ),
  );
  @override
  void discardInteractiveCaptcha(ConnectionMode route) {}
  @override
  void cancelInteractiveLogin() {}
}

class RecoveryProbeBackend extends ProbeBackend
    implements RequiredSessionBackend {
  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    delayRoute = true;
    return RecoveredRouteSession(
      route: ConnectionMode.webvpn,
      profile: profile!,
    );
  }

  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) => throw UnimplementedError();
}

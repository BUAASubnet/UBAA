part of '../app_controller_test.dart';

void _registerRaceTests() {
  test('controller 销毁后初始化不会继续读取用户或刷新首页', () async {
    final backend = _DelayedSignedInInitializeBackend();
    final controller = AppController(backend: backend);
    final initializing = controller.initialize();
    await backend.authStarted.future;

    controller.dispose();
    backend.releaseAuth.complete();
    await initializing;

    expect(backend.userInfoCalls, 0);
    expect(backend.featureLoads, 0);
  });

  test('controller 销毁后延迟登录不会继续读取用户或保存凭据', () async {
    final backend = _DelayedLoginBackend();
    final vault = MemoryCredentialVault();
    final controller = AppController(backend: backend, credentialVault: vault);
    controller.setUsername('student');
    controller.setPassword('secret');

    final loggingIn = controller.submitLogin();
    await backend.loginStarted.future;
    controller.dispose();
    backend.releaseLogin.complete();
    await loggingIn;

    expect(backend.userInfoCalls, 0);
    expect(vault.saveCount, 0);
  });

  test('controller 销毁后延迟路线设置不会回写策略', () async {
    final backend = _DelayedRoutePolicyBackend();
    final controller = AppController(backend: backend);

    final changing = controller.setRoutePolicy(RoutePolicy.webvpn);
    await backend.prepareStarted.future;
    controller.dispose();
    backend.releasePrepare.complete();
    await changing;

    expect(backend.routeSettingsCalls, 0);
    expect(controller.loginForm.routePolicy, RoutePolicy.auto);
  });

  test('controller 销毁后延迟注销不会回写登录状态', () async {
    final backend = _DelayedLogoutBackend();
    final controller = AppController(backend: backend);

    final loggingOut = controller.logout();
    await backend.logoutStarted.future;
    controller.dispose();
    backend.releaseLogout.complete();
    await loggingOut;

    expect(controller.phase, AppPhase.splash);
  });

  test('controller 销毁后延迟的功能读取不会回写快照', () async {
    final backend = _DelayedFeatureBackend();
    final controller = AppController(backend: backend);
    final refreshing = controller.refreshHome(
      only: const <FeatureId>[FeatureId.schedule],
    );
    await backend.loadStarted.future;

    expect(
      controller.snapshots[FeatureId.schedule]!.status,
      FeatureLoadStatus.loading,
    );
    controller.dispose();
    backend.releaseLoad.complete(
      const FeatureResult.success(
        summary: '不应回写',
        details: <FeatureDetail>[FeatureDetail(title: '不应回写')],
      ),
    );
    await refreshing;

    final snapshot = controller.snapshots[FeatureId.schedule]!;
    expect(snapshot.status, FeatureLoadStatus.loading);
    expect(snapshot.summary, isNull);
    expect(snapshot.details, isEmpty);
  });
}

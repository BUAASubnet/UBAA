part of '../app_controller_test.dart';

void _registerLifecycleTests() {
  test('宿主重建 backend 后重新读取认证和路线状态', () async {
    final first = _RebuildBackend(
      signedIn: false,
      activeRoutes: const <ConnectionMode>[],
    );
    final second = _RebuildBackend(
      signedIn: true,
      activeRoutes: const <ConnectionMode>[ConnectionMode.webvpn],
    );
    var factoryCalls = 0;
    final controller = AppController(
      backend: first,
      backendFactory: () {
        factoryCalls++;
        return second;
      },
    );
    await controller.initialize();
    expect(controller.phase, AppPhase.login);

    expect(await controller.rebuildBackend(), isTrue);
    expect(factoryCalls, 1);
    expect(first.disposed, isTrue);
    expect(controller.phase, AppPhase.home);
    expect(controller.user?.username, 'student');
    expect(controller.activeRoutes, <ConnectionMode>[ConnectionMode.webvpn]);
    controller.dispose();
  });

  test('初始化进行中时生命周期重建安全拒绝且不释放旧 backend', () async {
    final first = _DelayedInitializeBackend();
    final second = _RebuildBackend(
      signedIn: true,
      activeRoutes: const <ConnectionMode>[ConnectionMode.direct],
    );
    final controller = AppController(
      backend: first,
      backendFactory: () => second,
    );
    final initializing = controller.initialize();
    await first.authStarted.future;

    expect(controller.phase, AppPhase.checkingSession);
    expect(await controller.rebuildBackend(), isFalse);
    expect(first.disposed, isFalse);
    expect(second.disposed, isFalse);

    first.releaseAuth.complete();
    await initializing;
    expect(controller.phase, AppPhase.login);
    controller.dispose();
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  for (final fails in <bool>[false, true]) {
    test('再次选择原策略使较早${fails ? '失败' : '成功'}失效', () async {
      final backend = _RouteBackend(RoutePolicy.direct);
      final controller = AppController(backend: backend);
      addTearDown(controller.dispose);
      await controller.initialize();
      final pending = backend.delayNext();
      final old = controller.setRoutePolicy(RoutePolicy.webvpn);
      await pending.started.future;
      await controller.setRoutePolicy(RoutePolicy.direct);
      pending.finish(fails);
      await old;
      expect(controller.loginForm.routePolicy, RoutePolicy.direct);
      expect(controller.error, isNull);
      expect(backend.requested, <RoutePolicy>[
        RoutePolicy.webvpn,
        RoutePolicy.direct,
      ]);
    });
    test('路线切换在途时禁止重建，收尾后重建核对真实策略：$fails', () async {
      final previous = _RouteBackend(RoutePolicy.direct);
      final replacement = _RouteBackend(RoutePolicy.webvpn);
      final controller = AppController(
        backend: previous,
        backendFactory: () => replacement,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final pending = previous.delayNext();
      final change = controller.setRoutePolicy(RoutePolicy.webvpn);
      await pending.started.future;
      expect(await controller.rebuildBackend(), isFalse);
      expect(previous.disposed, isFalse);
      pending.finish(fails);
      await change;
      expect(await controller.rebuildBackend(), isTrue);
      expect(controller.loginForm.routePolicy, RoutePolicy.webvpn);
      expect(controller.error, isNull);
      expect(replacement.loginCalls, 0);
    });

    test('后续路线选择不能被旧${fails ? '失败' : '成功'}覆盖', () async {
      final backend = _RouteBackend(RoutePolicy.direct);
      final controller = AppController(backend: backend);
      addTearDown(controller.dispose);
      await controller.initialize();
      final pending = backend.delayNext();
      final old = controller.setRoutePolicy(RoutePolicy.webvpn);
      await pending.started.future;
      await controller.setRoutePolicy(RoutePolicy.auto);
      expect(controller.loginForm.routePolicy, RoutePolicy.auto);
      pending.finish(fails);
      await old;
      expect(controller.loginForm.routePolicy, RoutePolicy.auto);
      expect(controller.error, isNull);
      expect(backend.loginCalls, 0);
    });

    test('退出后旧路线${fails ? '失败' : '成功'}不能恢复状态', () async {
      final backend = _RouteBackend(RoutePolicy.direct);
      final controller = AppController(backend: backend);
      addTearDown(controller.dispose);
      await controller.initialize();
      final pending = backend.delayNext();
      final change = controller.setRoutePolicy(RoutePolicy.webvpn);
      await pending.started.future;
      await controller.logout();
      pending.finish(fails);
      await change;
      expect(controller.phase, AppPhase.login);
      expect(controller.user, isNull);
      expect(controller.activeRoutes, isEmpty);
      expect(controller.loginForm.routePolicy, RoutePolicy.direct);
      expect(controller.error, isNull);
    });
  }
}

class _PendingRoute {
  final started = Completer<void>();
  final release = Completer<void>();

  void finish(bool fails) {
    if (fails) {
      release.completeError(
        const BackendException(UbaaErrorCode.internalError),
      );
    } else {
      release.complete();
    }
  }
}

class _RouteBackend
    implements UbaaBackend, RouteSettingsBackend, BackendLifecycle {
  _RouteBackend(this.policy);

  RoutePolicy policy;
  _PendingRoute? pending;
  bool disposed = false;
  int loginCalls = 0;
  final requested = <RoutePolicy>[];

  _PendingRoute delayNext() => pending = _PendingRoute();

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic-route-account');

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: policy,
    activeRoutes: ConnectionMode.values,
  );

  @override
  Future<void> prepareLogin(RoutePolicy value) async {
    requested.add(value);
    final waiting = pending;
    pending = null;
    if (waiting != null) {
      waiting.started.complete();
      await waiting.release.future;
    }
    policy = value;
  }

  @override
  Future<void> login(LoginInput input) async => loginCalls++;

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<void> dispose() async => disposed = true;
}

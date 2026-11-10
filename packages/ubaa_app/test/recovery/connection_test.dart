import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import '../support/controller/clock_accounts.dart';

void main() {
  for (final automatic in [true, false]) {
    test('校内会话移动到校外按保存许可补登录：$automatic', () async {
      final backend = _Backend();
      final controller = AppController(
        backend: backend,
        localAccountStore: ClockAccounts(),
        credentialVault: MemoryCredentialVault(
          initial: Credential(
            username: 'fixture-user',
            password: 'synthetic',
            autoLogin: automatic,
          ),
        ),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.recoverSession(refreshHomeAfter: false);
      controller.onHomeFirstFrame();
      expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
      backend.offCampus = true;
      controller.onNetworkChanged();
      controller.onNetworkChanged();
      await controller.recoverSession();
      expect(backend.targets, [RecoveryTarget.connection]);
      expect(backend.logins, automatic ? [ConnectionMode.webvpn] : isEmpty);
      expect(
        controller.sessionRecoveryStatus,
        automatic
            ? SessionRecoveryStatus.ready
            : SessionRecoveryStatus.needsLogin,
      );
      if (!automatic)
        expect(controller.error?.code, UbaaErrorCode.authenticationRequired);
    });
  }

  test('网络变化发生在旧功能检查期间，完成后仍重新检测连接', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: ClockAccounts(),
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: 'fixture-user',
          password: 'synthetic',
          autoLogin: true,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(refreshHomeAfter: false);
    controller.onHomeFirstFrame();
    backend.featureGate = Completer<void>();
    final old = controller.recoverSession(refreshHomeAfter: false);
    await backend.started.future;
    backend.offCampus = true;
    controller.onNetworkChanged();
    final fresh = controller.recoverSession();
    backend.featureGate!.complete();
    await old;
    await fresh;
    expect(backend.targets, [RecoveryTarget.connection]);
    expect(backend.logins, [ConnectionMode.webvpn]);
  });

  test('回到前台重新检查连接会话，不只复用直连身份', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: ClockAccounts(),
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: 'fixture-user',
          password: 'synthetic',
          autoLogin: true,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(refreshHomeAfter: false);
    controller.setAppForeground(false);
    backend.offCampus = true;
    controller.setAppForeground(true);
    await controller.resumeSession();
    expect(backend.targets, [RecoveryTarget.connection]);
    expect(backend.logins, [ConnectionMode.webvpn]);
  });
}

class _Backend extends support.FakeRecoveryBackend
    implements RequiredTargetSessionBackend {
  Completer<void>? featureGate;
  final started = Completer<void>();
  bool offCampus = false;
  bool vpnReady = false;
  final targets = <RecoveryTarget>[];
  final logins = <ConnectionMode>[];
  RecoveredRouteSession session(ConnectionMode route) => RecoveredRouteSession(
    route: route,
    profile: const UserSummary(username: 'fixture-user'),
  );
  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async => session(ConnectionMode.direct);
  @override
  Future<RecoveredRouteSession> recoverTargetSession(
    RecoveryTarget target,
  ) async {
    if (target != RecoveryTarget.connection) {
      if (featureGate != null) {
        started.complete();
        await featureGate!.future;
      }
      return session(ConnectionMode.direct);
    }
    targets.add(target);
    if (target == RecoveryTarget.connection && offCampus && !vpnReady) {
      throw const BackendException(
        UbaaErrorCode.authenticationRequired,
        resolvedRoute: ConnectionMode.webvpn,
      );
    }
    return session(offCampus ? ConnectionMode.webvpn : ConnectionMode.direct);
  }

  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) async {
    logins.add(route);
    vpnReady = true;
    return session(route);
  }
}

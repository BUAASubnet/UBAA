import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_app/runtime.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import '../runtime/shared_recovery_probe.dart' as probe;
import '../runtime/session_recovery_probe.dart' show profile, saved;

void main() {
  late Directory root;
  setUp(() async {
    root = await probe.fixture();
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test('GUI 同账号恢复发布后重建一次客户端，旧客户端终态，继任正常交付', () async {
    final accounts = await probe.openAccounts(root);
    final first = _Backend(root);
    var rebuilt = 0;
    final controller = AppController(
      backend: first,
      localAccountStore: accounts,
      credentialVault: MemoryCredentialVault(initial: saved),
      backendFactory: () {
        rebuilt++;
        return _Backend(root);
      },
    );
    try {
      await controller.initialize();
      await controller.recoverSession(refreshHomeAfter: false);
      expect(controller.user!.username, profile.username);
      final other = probe.service(root);
      await probe.ensure(
        other,
        await probe.capture(await probe.openAccounts(root)),
      );
      await other.close();
      // 模拟外部 Core 活动刷新产生新 revision，旧客户端必须拒绝。
      await File('${root.path}/session').writeAsString('外部同账号会话');
      await expectLater(
        first.recoverRequiredSession(FeatureId.schedule),
        throwsA(isA<BackendException>()),
      );
      await controller.recoverSession(refreshHomeAfter: false);
      expect(rebuilt, 1);
      expect(first.disposed, isTrue);
      expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
      expect(controller.user!.username, profile.username);
      expect(
        controller.internalSharedAccountSnapshot!.state.canRestore,
        isTrue,
      );
    } finally {
      controller.dispose();
      await controller.internalDisposeBackendOnce(controller.internalBackend);
    }
  });
  for (final relogin in [false, true]) {
    test('GUI 客户端工厂挂起时外部退出，重登=$relogin，拒绝继任', () async {
      final accounts = await probe.openAccounts(root);
      final entered = Completer<void>(), release = Completer<void>();
      final first = _Backend(root), next = _Backend(root);
      final controller = AppController(
        backend: first,
        localAccountStore: accounts,
        credentialVault: MemoryCredentialVault(initial: saved),
        backendFactory: () async {
          entered.complete();
          await release.future;
          return next;
        },
      );
      try {
        await controller.initialize();
        await controller.recoverSession(refreshHomeAfter: false);
        await accounts.refreshIfCurrent((await accounts.capture())!);
        final recovering = controller.recoverSession(refreshHomeAfter: false);
        await entered.future;
        final external = await probe.openAccounts(root);
        await external.signOut();
        if (relogin)
          await external.retain(profile.username, retainSession: true);
        release.complete();
        await recovering;
        expect(next.disposed, isTrue);
        expect(
          controller.sessionRecoveryStatus,
          isNot(SessionRecoveryStatus.ready),
        );
      } finally {
        if (!release.isCompleted) release.complete();
        controller.dispose();
        await controller.internalDisposeBackendOnce(controller.internalBackend);
      }
    });
  }
}

class _Backend extends support.FakeRecoveryBackend
    implements RequiredSessionBackend, BackendLifecycle {
  _Backend(Directory root) : delegate = probe.FileBackend(root) {
    username = profile.username;
  }
  final probe.FileBackend delegate;
  bool disposed = false;
  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(FeatureId feature) =>
      delegate.recoverRequiredSession(feature);
  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) => delegate.loginRequiredRoute(route, input);
}

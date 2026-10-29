import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/recovery.dart' as support;

void main() {
  test('写意图确认期间合并恢复，取消安全收尾后自动开始一次检查', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    controller.writeCoordinator.setIntent(_intent());
    final first = controller.recoverSession();
    final second = controller.recoverSession();
    expect(identical(first, second), isTrue);
    expect(backend.authCalls, 1);
    expect(controller.writeCoordinator.intent, isNotNull);
    await controller.writeCoordinator.cancelForUi();
    await first;
    expect(backend.authCalls, 2);
    expect(backend.commits, 0);
  });
  test('后台等待在前台唤醒与显式恢复同时发生时仍只检查一次', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    controller.setAppForeground(false);
    final waiting = controller.recoverSession();
    expect(backend.authCalls, 1);
    controller.setAppForeground(true);
    final resumed = controller.resumeSession();
    await Future.wait([waiting, resumed]);
    expect(backend.authCalls, 2);
  });
  test('待确认意图存在时不得通过重建 backend 绕过写流程保护', () async {
    var created = 0;
    final controller = AppController(
      backend: _Backend(),
      backendFactory: () {
        created++;
        return _Backend();
      },
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    controller.writeCoordinator.setIntent(_intent());
    expect(await controller.rebuildBackend(), isFalse);
    expect(created, 0);
    expect(controller.writeCoordinator.intent?.intentId, 'synthetic');
  });
  test('旧宿主返回前台不能自动提交另一个账号的已存密码', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: 'another-fixture',
          password: 'synthetic',
          autoLogin: true,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    backend.signedIn = false;
    await controller.resumeSession();
    expect(backend.loginCalls, 0);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.needsLogin);
    expect(controller.phase, AppPhase.home);
  });
  for (final unknown in [false, true]) {
    test('恢复等待单次提交及回读，结果未知=$unknown 也不自动重发', () async {
      final backend = _Backend()..syntheticOutcomeUnknown = unknown;
      final controller = AppController(
        backend: backend,
        localAccountStore: await support.savedAccounts(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.recoverSession();
      controller.writeCoordinator.setIntent(_intent());
      final recovery = controller.recoverSession();
      final outcome = await controller.writeCoordinator.confirmForUi();
      await recovery;
      expect(backend.commits, 1);
      expect(backend.authCalls, 2);
      if (unknown) {
        expect(outcome?.result?.outcomeUnknown, isTrue);
        expect(outcome?.result?.success, isFalse);
      } else {
        expect(outcome?.result?.success, isTrue);
      }
    });
  }
  test('等待写流程的恢复遇主动退出后取消，不重新登录或重开首页', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    controller.writeCoordinator.setIntent(_intent());
    final recovery = controller.recoverSession();
    await controller.logout();
    await recovery;
    expect(backend.authCalls, 1);
    expect(controller.phase, AppPhase.login);
  });
}

WriteIntent _intent() => WriteIntent(
  intentId: 'synthetic',
  operation: WriteOperation.bykcSelectCourse,
  targetSummary: '合成目标',
  resolvedRoute: ConnectionMode.direct,
  warnings: const [],
  expiresAt: DateTime.now().add(const Duration(minutes: 2)),
  requestDigest: 'synthetic',
);

class _Backend extends support.FakeRecoveryBackend
    implements WriteCommitBackend {
  int commits = 0;
  bool? syntheticOutcomeUnknown;
  @override
  Future<void> discardWriteIntent(String intentId) async {}
  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commits++;
    final unknown = syntheticOutcomeUnknown;
    if (unknown == null) throw StateError('该恢复测试禁止提交');
    return WriteCommitResult(
      operation: WriteOperation.bykcSelectCourse,
      success: !unknown,
      message: '合成结果',
      outcomeUnknown: unknown,
    );
  }
}

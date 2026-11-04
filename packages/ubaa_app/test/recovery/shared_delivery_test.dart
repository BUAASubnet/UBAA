import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/runtime.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import '../../../ubaa_platform/test/support/shared_account_worker.dart'
    show syntheticWindowsMaterials;
import '../runtime/shared_recovery_probe.dart' as probe;
import '../runtime/session_recovery_probe.dart' show saved, failure;

void main() {
  test('成功交付后立即复用返回 scope，同功能新消费者独立完成', () async {
    final root = await probe.fixture();
    final accounts = await probe.openAccounts(root);
    final recovery = probe.service(root);
    try {
      final first = await probe.ensure(recovery, await probe.capture(accounts));
      final second = await recovery
          .ensureRequiredSession(
            feature: FeatureId.schedule,
            scope: first.scope!,
            deadline: DateTime.now().add(const Duration(seconds: 1)),
          )
          .timeout(const Duration(seconds: 3));
      expect(second.session.profile.username, first.session.profile.username);
      expect(
        second.scope!.accountGeneration,
        (await accounts.read())!.generation,
      );
      expect(second.disposition, RecoveryDisposition.reused);
      expect((await recovery.close()).settled, isTrue);
    } finally {
      await recovery.close();
      await root.delete(recursive: true);
    }
  });

  test('失败交付后立即重试，同功能新消费者仍有明确终态', () async {
    final root = await probe.fixture();
    final accounts = await probe.openAccounts(root);
    final scope = await probe.capture(accounts);
    final recovery = probe.service(
      root,
      backend: probe.FileBackend(
        root,
        recoveryError: const BackendException(UbaaErrorCode.networkError),
      ),
    );
    try {
      final first = await failure(probe.ensure(recovery, scope));
      expect((first as BackendException).code, UbaaErrorCode.networkError);
      final second = await failure(
        probe.ensure(recovery, scope),
      ).timeout(const Duration(seconds: 3));
      expect((second as BackendException).code, UbaaErrorCode.networkError);
      expect((await recovery.close()).settled, isTrue);
    } finally {
      await recovery.close();
      await root.delete(recursive: true);
    }
  });

  for (final stop in ['取消', '期限', '局部失效']) {
    test('材料交付等待期间$stop首消费者，其余消费者仍正常交付', () async {
      final root = await probe.fixture();
      final transport = _PausingDeliveryRead(syntheticWindowsMaterials(root));
      final materials = SecureMaterialStore(
        transport: transport,
        coordinator: MaterialCoordinator(
          directory: Directory('${root.path}/lock'),
        ),
      );
      await materials.probe();
      final accounts = SecureLocalAccountStore(materials);
      var current = true;
      final firstScope = await RecoveryScope.capture(
        accounts: accounts,
        routeGeneration: 1,
        backendGeneration: 1,
        credentialGeneration: 1,
        routePolicy: RoutePolicy.direct,
        allowAutomaticLogin: true,
        isCurrent: () => current,
      );
      final secondScope = await probe.capture(accounts);
      final recovery = RequiredSessionRecovery(
        backend: probe.FileBackend(root),
        credentials: MemoryCredentialVault(initial: saved),
      );
      final cancellation = RecoveryCancellation();
      transport.armed = true;
      try {
        final one = _observe(
          recovery.ensureRequiredSession(
            feature: FeatureId.schedule,
            scope: firstScope,
            deadline: DateTime.now().add(
              stop == '期限'
                  ? const Duration(seconds: 2)
                  : const Duration(seconds: 10),
            ),
            cancellation: cancellation,
          ),
        );
        final two = _observe(probe.ensure(recovery, secondScope));
        await transport.entered.future.timeout(const Duration(seconds: 5));
        if (stop == '取消') cancellation.cancel();
        if (stop == '局部失效') {
          current = false;
          recovery.validateScopes();
        }
        final first = await one.timeout(const Duration(seconds: 5));
        expect(first, isA<RecoveryInterrupted>());
        expect(
          (first as RecoveryInterrupted).reason,
          stop == '取消'
              ? RecoveryStopReason.cancelled
              : stop == '期限'
              ? RecoveryStopReason.deadline
              : RecoveryStopReason.superseded,
        );
        transport.release.complete();
        final second = await two.timeout(const Duration(seconds: 5));
        expect(second, isA<RecoveryResult>());
        expect((await accounts.read())!.canRestore, isTrue);
        expect((await recovery.close()).settled, isTrue);
      } finally {
        if (!transport.release.isCompleted) transport.release.complete();
        await recovery.close();
        await root.delete(recursive: true);
      }
    });
  }
}

Future<Object> _observe(Future<RecoveryResult> pending) async {
  try {
    return await pending;
  } on Object catch (error) {
    return error;
  }
}

/// 暂停恢复发布后的交付读取，使用真实材料事务与合成文件传输。
class _PausingDeliveryRead implements SecureMaterialTransport {
  _PausingDeliveryRead(this.delegate);
  final SecureMaterialTransport delegate;
  final entered = Completer<void>(), release = Completer<void>();
  bool armed = false, published = false;
  int reads = 0;
  @override
  Future<void> write(String key, String value) async {
    await delegate.write(key, value);
    if (armed && key.endsWith('account-index.v1')) {
      published = true;
      reads = 0;
    }
  }

  @override
  Future<String?> read(String key) async {
    final value = await delegate.read(key);
    if (published && key.endsWith('account-index.v1') && ++reads == 2) {
      // 写入后第一次读取属于写后校验，第二次读取属于 commitDelivery。
      expect(jsonDecode(value!)['canRestore'], isTrue);
      entered.complete();
      await release.future;
    }
    return value;
  }

  @override
  Future<void> delete(String key) => delegate.delete(key);
}

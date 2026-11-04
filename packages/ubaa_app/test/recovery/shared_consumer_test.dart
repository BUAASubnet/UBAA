import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/runtime.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import '../runtime/shared_recovery_probe.dart' as fixture;
import '../runtime/session_recovery_probe.dart' as pure;

class _Backend implements BackendLifecycle, SharedAccountBackend {
  final disposeGate = Completer<void>();
  int closes = 0;
  SharedAccountBinding? binding;
  @override
  Future<void> bindSharedAccount(SharedAccountBinding binding) async {
    this.binding = binding;
  }

  @override
  Future<void> dispose() {
    closes++;
    return disposeGate.future;
  }
}

class _HangingRecovery implements RequiredSessionBackend {
  final entered = Completer<void>();
  final release = Completer<RecoveredRouteSession>();
  @override
  Future<RecoveredRouteSession> recoverRequiredSession(FeatureId feature) {
    entered.complete();
    return release.future;
  }

  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) => throw StateError('不得登录');
}

void main() {
  test('普通关闭有界返回但保管未完成资源，许可和另一消费者保持', () async {
    final root = await fixture.fixture();
    final store = await fixture.openAccounts(root);
    final a = _Backend(), b = _Backend();
    final one = SharedAccountConsumer(backend: a, accounts: a);
    final two = SharedAccountConsumer(backend: b, accounts: b);
    try {
      final snapshot = (await store.capture())!;
      await one.bind(store, snapshot);
      await two.bind(store, snapshot);
      final result = await one.close(grace: Duration.zero);
      expect(result.settled, isFalse);
      expect(a.closes, 1);
      await expectLater(
        one.bind(store, snapshot),
        throwsA(isA<RecoveryInterrupted>()),
      );
      await b.binding!.validate();
      expect((await store.read())!.canRestore, isTrue);
      a.disposeGate.complete();
      await one.settlement;
      expect((await one.close()).settled, isTrue);
      expect(a.closes, 1);
    } finally {
      if (!a.disposeGate.isCompleted) a.disposeGate.complete();
      if (!b.disposeGate.isCompleted) b.disposeGate.complete();
      await one.close();
      await two.close();
      await root.delete(recursive: true);
    }
  });
  test('学校写准备提交和回读期间拒绝换绑，外部撤销后的新写不进入执行器', () async {
    final root = await fixture.fixture();
    final store = await fixture.openAccounts(root);
    final backend = _Backend();
    final consumer = SharedAccountConsumer(backend: backend, accounts: backend);
    final entered = Completer<void>(), release = Completer<void>();
    try {
      final snapshot = (await store.capture())!;
      await consumer.bind(store, snapshot);
      final writing = consumer.schoolWrite(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      await expectLater(
        consumer.bind(store, snapshot),
        throwsA(isA<RecoveryInterrupted>()),
      );
      await (await fixture.openAccounts(root)).signOut();
      release.complete();
      await writing;
      var called = false;
      await expectLater(
        consumer.schoolWrite(() async {
          called = true;
        }),
        throwsA(isA<LocalAccountConflict>()),
      );
      expect(called, isFalse);
    } finally {
      if (!release.isCompleted) release.complete();
      backend.disposeGate.complete();
      await consumer.close();
      await root.delete(recursive: true);
    }
  });
  test('消费者关闭等待恢复排空，资源已释放仍不能过早报告 settled', () async {
    final backend = _Backend()..disposeGate.complete();
    final hanging = _HangingRecovery();
    final recovery = RequiredSessionRecovery(
      backend: hanging,
      credentials: MemoryCredentialVault(),
    );
    final consumer = SharedAccountConsumer(
      backend: backend,
      accounts: backend,
      recovery: recovery,
    );
    final pending = pure.failure(
      recovery.ensureRequiredSession(
        feature: FeatureId.schedule,
        scope: pure.scope(),
        deadline: DateTime.now().add(const Duration(seconds: 10)),
      ),
    );
    await hanging.entered.future;
    try {
      final result = await consumer.close(grace: Duration.zero);
      expect(await pending, isA<RecoveryInterrupted>());
      expect(recovery.pendingOperations, 1);
      expect(result.settled, isFalse);
      hanging.release.complete(
        const RecoveredRouteSession(
          route: ConnectionMode.direct,
          profile: pure.profile,
        ),
      );
      await consumer.settlement;
      expect(recovery.pendingOperations, 0);
      expect((await consumer.close()).settled, isTrue);
    } finally {
      if (!hanging.release.isCompleted)
        hanging.release.complete(
          const RecoveredRouteSession(
            route: ConnectionMode.direct,
            profile: pure.profile,
          ),
        );
      await recovery.close();
      await consumer.close();
    }
  });
  test('消费者关闭也等待已接受的学校写单元返回，不只等待 backend dispose', () async {
    final root = await fixture.fixture();
    final store = await fixture.openAccounts(root);
    final backend = _Backend()..disposeGate.complete();
    final consumer = SharedAccountConsumer(backend: backend, accounts: backend);
    final entered = Completer<void>(), release = Completer<void>();
    await consumer.bind(store, (await store.capture())!);
    final writing = consumer.schoolWrite(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    try {
      expect((await consumer.close(grace: Duration.zero)).settled, isFalse);
      release.complete();
      await writing;
      await consumer.settlement;
      expect((await consumer.close()).settled, isTrue);
    } finally {
      if (!release.isCompleted) release.complete();
      await writing;
      await consumer.close();
      await root.delete(recursive: true);
    }
  });
  test('有界关闭后晚到资源错误仍由 settlement 交付', () async {
    final backend = _Backend();
    final consumer = SharedAccountConsumer(backend: backend, accounts: backend);
    expect((await consumer.close(grace: Duration.zero)).settled, isFalse);
    final observed = expectLater(
      consumer.settlement,
      throwsA(isA<StateError>()),
    );
    backend.disposeGate.completeError(StateError('合成收尾失败'));
    await observed;
    await expectLater(consumer.close(), throwsA(isA<StateError>()));
  });
}

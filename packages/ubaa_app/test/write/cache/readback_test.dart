import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import '../../../../ubaa_platform/test/support/test_tmp.dart';
import '../../recovery/backend_rebuild/fakes.dart' as base;

void main() {
  test('预读进入首页后补读待核实提示，认证挂起也不自动提交', () async {
    final backend = HintBackend()..gate = Completer<AuthStatus>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    var firstHome = true;
    controller.addListener(() {
      if (firstHome && controller.phase == AppPhase.home) {
        firstHome = false;
        expect(backend.hintReads, 0, reason: '预读阶段不加载写入核对提示');
        expect(
          controller.homeSnapshots[FeatureId.schedule]!.details,
          isNotEmpty,
        );
      }
    });
    await base.cachedHome(controller, backend);
    expect(backend.hintReads, 1);
    expect(backend.authCalls, 0);
    expect(controller.writeCoordinator.intent, isNull);
    expect(controller.writeReadbacks.single.id, backend.hints.single.id);
    expect(controller.writeReadbacks.single.feature, FeatureId.signin);
  });

  test('未知提交完成后重读提示，不合并到提交前的迟到空读取', () async {
    final backend = HintBackend()
      ..firstReadGate = Completer<void>()
      ..hints.clear();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await base.cachedHome(controller, backend);
    await controller.recoverSession(refreshHomeAfter: false);
    controller.writeCoordinator.setIntent(base.intent());
    final outcome = await controller.writeCoordinator.confirmForUi();
    backend.firstReadGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(outcome?.result?.outcomeUnknown, isTrue);
    expect(backend.commits, 1);
    expect(controller.writeReadbacks, hasLength(1));
    expect(controller.writeCoordinator.intent, isNull);
  });

  test('共享恢复交付强制重读提示，绑定期间开始的普通读取不能覆盖新结果', () async {
    final root = createTestTempDirectory('ubaa_app_write_readback');
    addTearDown(() => root.delete(recursive: true));
    final materials = SecureMaterialStore(
      coordinator: MaterialCoordinator(directory: root),
      transport: support.MemoryMaterials(),
    );
    await materials.probe();
    final accounts = SecureLocalAccountStore(materials);
    final backend = _SharedHintBackend();
    await accounts.retain(backend.username, retainSession: true);
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    final oldReadStarted = Completer<void>(),
        oldReadRelease = Completer<void>();
    try {
      await base.cachedHome(controller, backend);
      await controller.internalWriteReadbackRead?.completion.future;
      expect(backend.hintReads, 1);
      // 恢复先绑定当前索引，再绑定用于最终交付的新索引。等待最后一次，
      // 避免第二次重绑提前作废普通读取，掩盖交付漏掉的强制刷新。
      backend.pauseBindingAt = backend.bindingGeneration + 2;
      final recovery = controller.recoverSession(refreshHomeAfter: false);
      await backend.bindingStarted.future;
      final oldHint = backend.hints.single;
      backend.onHintRead = (number) async {
        if (number != 2) return;
        oldReadStarted.complete();
        await oldReadRelease.future;
      };
      final oldRead = controller.internalLoadWriteReadbacks();
      await oldReadStarted.future;
      backend.hints.clear();
      backend.bindingRelease.complete();
      await recovery;
      expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
      expect(backend.hintReads, 3);
      await controller.internalWriteReadbackRead?.completion.future;
      expect(controller.writeReadbacks, isEmpty);
      oldReadRelease.complete();
      await oldRead;
      expect(controller.writeReadbacks, isNot(contains(oldHint)));
      expect(controller.writeReadbackError, isNull);
      expect(backend.commits, 0);
    } finally {
      if (!oldReadRelease.isCompleted) oldReadRelease.complete();
      if (!backend.bindingRelease.isCompleted)
        backend.bindingRelease.complete();
      controller.dispose();
      await controller.internalDisposeBackendOnce(backend);
    }
  });

  test('共享恢复重绑尚未完成时旧提示读取作废，不记录冲突', () async {
    final root = createTestTempDirectory('ubaa_app_write_readback');
    addTearDown(() => root.delete(recursive: true));
    final materials = SecureMaterialStore(
      coordinator: MaterialCoordinator(directory: root),
      transport: support.MemoryMaterials(),
    );
    await materials.probe();
    final accounts = SecureLocalAccountStore(materials);
    final backend = _SharedHintBackend()..firstReadGate = Completer<void>();
    await accounts.retain(backend.username, retainSession: true);
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    try {
      await base.cachedHome(controller, backend);
      expect(backend.hintReads, 1);
      final startup = controller.internalWriteReadbackRead!.completion.future;
      backend.pauseBindingAt = backend.bindingGeneration + 1;
      final recovery = controller.recoverSession(refreshHomeAfter: false);
      await backend.bindingStarted.future;
      backend.firstReadGate!.complete();
      await startup;
      expect(controller.writeReadbackError, isNull);
      expect(controller.diagnostics.records, isEmpty);
      backend.bindingRelease.complete();
      await recovery;
      expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
      final refreshed = controller.internalWriteReadbackRead?.completion.future;
      await refreshed;
      expect(backend.hintReads, 2);
      expect(controller.writeReadbacks, hasLength(1));
      expect(controller.writeReadbackError, isNull);
      expect(backend.commits, 0);
    } finally {
      if (!backend.firstReadGate!.isCompleted)
        backend.firstReadGate!.complete();
      if (!backend.bindingRelease.isCompleted)
        backend.bindingRelease.complete();
      controller.dispose();
      await controller.internalDisposeBackendOnce(backend);
    }
  });

  test('提示读取失败保留旧提示，明确报本地故障且不改学校结果', () async {
    final backend = HintBackend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await base.cachedHome(controller, backend);
    backend.readError = const BackendException(
      UbaaErrorCode.internalError,
      cacheFailure: CacheMaintenanceFailure.corrupt,
    );
    await controller.refreshWriteReadbacks();
    expect(controller.writeReadbacks, hasLength(1));
    expect(controller.writeReadbackError?.code, UbaaErrorCode.internalError);
    expect(backend.commits, 0);
    expect(backend.authCalls, 0);
  });

  test('写流程未结束不能移除待核实提示，删除失败仍保留提示', () async {
    final backend = HintBackend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await base.cachedHome(controller, backend);
    await controller.recoverSession(refreshHomeAfter: false);
    final id = controller.writeReadbacks.single.id;
    controller.writeCoordinator.setIntent(base.intent());
    await expectLater(
      controller.dismissWriteReadback(id),
      throwsA(isA<BackendException>()),
    );
    expect(backend.dismissals, 0);
    await controller.writeCoordinator.cancelForUi();
    backend.deleteError = true;
    await expectLater(
      controller.dismissWriteReadback(id),
      throwsA(isA<BackendException>()),
    );
    expect(controller.writeReadbacks, hasLength(1));
    backend.deleteError = false;
    await controller.dismissWriteReadback(id);
    expect(controller.writeReadbacks, isEmpty);
    expect(backend.commits, 0);
  });

  test('退出后迟到提示不能重新出现或触发提交', () async {
    final backend = HintBackend()..firstReadGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await base.cachedHome(controller, backend);
    await controller.logout();
    backend.firstReadGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.writeReadbacks, isEmpty);
    expect(controller.writeReadbackError, isNull);
    expect(backend.commits, 0);
  });

  test('显式清理本机内容同时清除核对提示，保留会话入口', () async {
    final backend = HintBackend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await base.cachedHome(controller, backend);
    await controller.clearBusinessCache(accountId: controller.cacheAccountId!);
    expect(controller.writeReadbacks, isEmpty);
    expect(controller.phase, AppPhase.home);
    expect(backend.hints, isEmpty);
    expect(backend.commits, 0);
  });
}

class HintBackend extends base.Backend
    implements WriteReadbackBackend, CacheWriteBackend, CacheManagementBackend {
  int hintReads = 0, commits = 0, dismissals = 0;
  Completer<void>? firstReadGate;
  Future<void> Function(int)? onHintRead;
  BackendException? readError;
  bool deleteError = false;
  final hints = [
    WriteReadbackHint(
      id: '0123456789abcdef0123456789abcdef',
      operation: WriteOperation.signinPerform,
      route: ConnectionMode.direct,
      startedAt: DateTime.utc(2026, 9, 23),
    ),
  ];
  @override
  Future<List<WriteReadbackHint>> readWriteReadbackHints({
    required String accountId,
  }) async {
    hintReads++;
    final values = List.of(hints);
    if (hintReads == 1) await firstReadGate?.future;
    await onHintRead?.call(hintReads);
    if (readError case final error?) throw error;
    return values;
  }

  @override
  Future<void> dismissWriteReadbackHint(
    String id, {
    required String accountId,
  }) async {
    dismissals++;
    if (deleteError)
      throw const BackendException(
        UbaaErrorCode.internalError,
        cacheFailure: CacheMaintenanceFailure.unavailable,
      );
    hints.removeWhere((hint) => hint.id == id);
  }

  @override
  Future<WriteCommitResult> commitWriteWithCache(
    String intentId, {
    required String accountId,
  }) async {
    commits++;
    hints.add(
      WriteReadbackHint(
        id: 'abcdef0123456789abcdef0123456789',
        operation: WriteOperation.bykcSelectCourse,
        route: ConnectionMode.direct,
        startedAt: DateTime.utc(2026, 9, 23),
      ),
    );
    return const WriteCommitResult(
      operation: WriteOperation.bykcSelectCourse,
      success: false,
      outcomeUnknown: true,
      message: '合成未知结果',
    );
  }

  @override
  Future<CacheClearOutcome> clearBusinessCache({
    required String accountId,
  }) async {
    hints.clear();
    return const CacheClearOutcome(compacted: true);
  }

  @override
  Future<CacheUsageSummary> cacheUsage({required String accountId}) =>
      throw UnimplementedError();
}

class _SharedHintBackend extends HintBackend
    implements RequiredSessionBackend, SharedAccountBackend {
  int bindingGeneration = 0;
  int? pauseBindingAt;
  final bindingStarted = Completer<void>(), bindingRelease = Completer<void>();
  @override
  Future<void> bindSharedAccount(SharedAccountBinding binding) async {
    await binding.validate();
    bindingGeneration++;
    if (bindingGeneration == pauseBindingAt) {
      bindingStarted.complete();
      await bindingRelease.future;
    }
  }

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async => RecoveredRouteSession(
    route: ConnectionMode.direct,
    profile: UserSummary(username: username),
  );
  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) => throw StateError('共享恢复测试禁止登录请求');
  @override
  Future<List<WriteReadbackHint>> readWriteReadbackHints({
    required String accountId,
  }) async {
    final generation = bindingGeneration;
    final values = await super.readWriteReadbackHints(accountId: accountId);
    if (generation != bindingGeneration)
      throw const BackendException(UbaaErrorCode.operationConflict);
    return values;
  }
}

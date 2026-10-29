import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import '../../recovery/backend_rebuild/fakes.dart' as base;

void main() {
  test('恢复缓存账号时独立读取重启核对提示，认证挂起也不自动提交', () async {
    final backend = HintBackend()..gate = Completer<AuthStatus>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
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

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../startup_test.dart' as support;

const query = FeatureQuery(page: 2, term: 'synthetic-term');
final conflict = throwsA(
  isA<BackendException>().having(
    (e) => e.code,
    '冲突',
    UbaaErrorCode.operationConflict,
  ),
);
void main() {
  Future<AppController> setup(_Backend backend) async {
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.onHomeFirstFrame();
    await controller.recoverSession(refreshHomeAfter: false);
    await Future<void>.delayed(Duration.zero);
    return controller;
  }

  test('待确认意图原样保留，清理不隐式取消或提交', () async {
    final backend = _Backend();
    final controller = await setup(backend);
    final intent = WriteIntent(
      intentId: 'synthetic',
      operation: WriteOperation.bykcSelectCourse,
      targetSummary: '合成目标',
      resolvedRoute: ConnectionMode.direct,
      warnings: const [],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'synthetic',
    );
    controller.writeCoordinator.setIntent(intent);
    expect(controller.canClearBusinessCache, isFalse);
    await expectLater(
      controller.clearBusinessCache(accountId: controller.cacheAccountId!),
      conflict,
    );
    expect(controller.writeCoordinator.intent, same(intent));
    expect(backend.clearCalls, 0);
  });
  test('清理保留登录和查询位置，取消迟到读取且不自动回填', () async {
    final backend = _Backend();
    final controller = await setup(backend);
    await controller.refreshFeatureQuery(FeatureId.classroom, query);
    final user = controller.user;
    final authCalls = backend.authCalls;
    final epoch = controller.readCacheEpoch;
    backend.readGate = Completer<FeatureResult>();
    final pending = controller.retryFeature(FeatureId.classroom);
    await backend.readStarted.future;
    backend.clearGate = Completer<void>();
    final clearing = controller.clearBusinessCache(
      accountId: controller.cacheAccountId!,
    );
    expect(controller.isClearingBusinessCache, isTrue);
    await controller.refreshHome();
    await controller.refreshFeatureQuery(
      FeatureId.schedule,
      const FeatureQuery(),
    );
    final calls = backend.readCalls;
    backend.clearGate!.complete();
    await clearing;
    backend.readGate!.complete(const FeatureResult.success(summary: '迟到内容'));
    await pending;
    expect(controller.user, same(user));
    expect(controller.phase, AppPhase.home);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
    expect(
      controller.snapshots[FeatureId.classroom]!.readContext!.hasSameQuery(
        query,
      ),
      isTrue,
    );
    expect(controller.snapshots[FeatureId.classroom]!.details, isEmpty);
    expect(controller.snapshots[FeatureId.classroom]!.summary, isNot('迟到内容'));
    expect(controller.readCacheEpoch, epoch);
    expect(controller.businessCacheEpoch, 1);
    expect(backend.readCalls, calls);
    expect(backend.authCalls, authCalls);
    expect(backend.signedIn, isTrue);
  });
  test('清理失败保留内容和查询且不留下永久loading', () async {
    final backend = _Backend();
    final controller = await setup(backend);
    await controller.refreshFeatureQuery(FeatureId.classroom, query);
    backend.readGate = Completer<FeatureResult>();
    final pending = controller.retryFeature(FeatureId.classroom);
    await backend.readStarted.future;
    backend.failClear = true;
    await expectLater(
      controller.clearBusinessCache(accountId: controller.cacheAccountId!),
      throwsA(isA<BackendException>()),
    );
    backend.readGate!.complete(const FeatureResult.empty());
    await pending;
    final snapshot = controller.snapshots[FeatureId.classroom]!;
    expect(snapshot.details.single.title, '合成教室');
    expect(snapshot.status, FeatureLoadStatus.stale);
    expect(controller.isClearingBusinessCache, isFalse);
    expect(controller.businessCacheEpoch, 0);
    expect(snapshot.readContext!.hasSameQuery(query), isTrue);
  });
  test('提交后维护失败仍清除内存并按报告反馈', () async {
    final backend = _Backend()
      ..maintenanceError = CacheMaintenanceFailure.capacity;
    final controller = await setup(backend);
    await controller.refreshFeatureQuery(FeatureId.classroom, query);
    final result = await controller.clearBusinessCache(
      accountId: controller.cacheAccountId!,
    );
    expect(result.maintenanceError, CacheMaintenanceFailure.capacity);
    expect(controller.snapshots[FeatureId.classroom]!.details, isEmpty);
    expect(controller.businessCacheEpoch, 1);
  });
  test('错误账号和正在恢复期间拒绝清理', () async {
    final backend = _Backend();
    final controller = await setup(backend);
    await expectLater(
      controller.clearBusinessCache(accountId: 'other'),
      conflict,
    );
    backend.gate = Completer<AuthStatus>();
    final recovery = controller.recoverSession(refreshHomeAfter: false);
    expect(
      (await controller.cacheUsage(
        accountId: controller.cacheAccountId!,
      )).entryCount,
      1,
    );
    await expectLater(
      controller.clearBusinessCache(accountId: controller.cacheAccountId!),
      conflict,
    );
    expect(backend.clearCalls, 0);
    backend.gate!.complete(AuthStatus.signedIn);
    await recovery;
  });
  test('清理期间禁止准备写入且不会自动提交，旧确认在退出后失效', () async {
    final backend = _Backend()..clearGate = Completer<void>();
    final controller = await setup(backend);
    final id = controller.cacheAccountId!;
    final clearing = controller.clearBusinessCache(accountId: id);
    var prepared = 0;
    expect(
      await controller.writeCoordinator.prepare(() async {
        prepared++;
        throw StateError('不得调用学校写入');
      }),
      isNull,
    );
    expect(prepared, 0);
    await controller.logout();
    backend.clearGate!.complete();
    await expectLater(clearing, conflict);
    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    await expectLater(controller.clearBusinessCache(accountId: id), conflict);
  });
}

class _Backend extends support.FakeRecoveryBackend
    implements
        CacheManagementBackend,
        OfflineCacheBackend,
        FeatureQueryBackend {
  Completer<void>? clearGate;
  Completer<FeatureResult>? readGate;
  final readStarted = Completer<void>();
  bool failClear = false;
  int clearCalls = 0;
  CacheMaintenanceFailure? maintenanceError;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    readCalls++;
    if (readGate != null) {
      if (!readStarted.isCompleted) readStarted.complete();
      return readGate!.future;
    }
    return const FeatureResult.success(details: [FeatureDetail(title: '合成教室')]);
  }

  @override
  Future<CacheUsageSummary> cacheUsage({required String accountId}) async =>
      CacheUsageSummary(
        accountId: accountId,
        entryCount: 1,
        contentBytes: 20,
        databaseBytes: 4096,
        reusableBytes: 0,
        softLimitBytes: 50,
        hardLimitBytes: 100,
      );
  @override
  Future<CacheClearOutcome> clearBusinessCache({
    required String accountId,
  }) async {
    clearCalls++;
    await clearGate?.future;
    if (failClear) throw const BackendException(UbaaErrorCode.internalError);
    return CacheClearOutcome(
      compacted: maintenanceError == null,
      maintenanceError: maintenanceError,
    );
  }

  @override
  Future<void> openOfflineAccount(LocalAccount account, List<int> key) async {}
  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) async =>
      OfflineHomeRead([]);
  @override
  Future<void> deactivateOfflineAccount() async {}
  @override
  Future<void> clearOfflineAccount() async {}
}

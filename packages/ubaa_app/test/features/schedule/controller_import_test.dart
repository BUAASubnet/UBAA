import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import '../../cache/query_test.dart' show until;

void main() {
  Future<AppController> setup(_Backend backend) async {
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(refreshHomeAfter: false);
    return controller;
  }

  test('重复导入合并，逐批让位紧急读取且不改当前查询', () async {
    final backend = _Backend();
    final controller = await setup(backend);
    const query = FeatureQuery(
      view: FeatureQueryView.scheduleWeek,
      term: 'selected',
      week: 3,
    );
    await controller.refreshFeatureQuery(FeatureId.schedule, query);
    backend.events.clear();
    final importing = controller.saveScheduleSemester('selected');
    final duplicate = controller.saveScheduleSemester('selected');
    await until(() => backend.task.pending.isNotEmpty);
    final urgent = controller.refreshFeatureQuery(
      FeatureId.signin,
      const FeatureQuery(),
    );
    backend.task.release(finished: false);
    await until(() => backend.events.contains('signin'));
    await urgent;
    await until(() => backend.task.pending.isNotEmpty);
    expect(backend.events, ['begin', 'batch', 'signin', 'batch']);
    backend.task.release(finished: true);
    await Future.wait([importing, duplicate]);
    expect(
      controller.scheduleImports['selected']!.status,
      ScheduleImportStatus.saved,
    );
    expect(
      controller.snapshots[FeatureId.schedule]!.readContext!.hasSameQuery(
        query,
      ),
      isTrue,
    );
  });
  for (final view in [
    FeatureQueryView.scheduleWeek,
    FeatureQueryView.summary,
  ]) {
    test('$view整学期刷新后从本地更新当前周，不额外请求单周', () async {
      final backend = _Backend();
      final controller = await setup(backend);
      final query = FeatureQuery(view: view, term: 'selected', week: 3);
      await controller.refreshFeatureQuery(FeatureId.schedule, query);
      final revision = controller.snapshots[FeatureId.schedule]!.readContext;
      backend.events.clear();
      final importing = controller.saveScheduleSemester('selected');
      await until(() => backend.task.pending.isNotEmpty);
      backend.cached = CachedFeatureProjection(
        feature: FeatureId.schedule,
        accountId: controller.cacheAccountId!,
        route: ConnectionMode.direct,
        fetchedAt: DateTime.utc(2026, 10, 23),
        complete: true,
        query: query,
        details: const [FeatureDetail(title: '更新后的课程')],
      );
      backend.task.release(finished: true);
      await importing;
      final snapshot = controller.snapshots[FeatureId.schedule]!;
      expect(snapshot.details.single.title, '更新后的课程');
      expect(snapshot.readContext, same(revision));
      expect(snapshot.evidence!.fetchedAt, DateTime.utc(2026, 10, 23));
      expect(backend.events, ['begin', 'batch']);
      expect(backend.cachePolicies.last, RoutePolicy.direct);
    });
  }

  for (final invalid in ['账号', '路线', '查询', '完整度', '读取失败']) {
    test('导入完成后拒绝$invalid异常投影，保留可见课表', () async {
      final backend = _Backend();
      final controller = await setup(backend);
      const query = FeatureQuery(
        view: FeatureQueryView.scheduleWeek,
        term: 'selected',
        week: 3,
      );
      await controller.refreshFeatureQuery(FeatureId.schedule, query);
      final previous = controller.snapshots[FeatureId.schedule];
      final importing = controller.saveScheduleSemester('selected');
      await until(() => backend.task.pending.isNotEmpty);
      backend.cached = CachedFeatureProjection(
        feature: FeatureId.schedule,
        accountId: invalid == '账号' ? 'other' : controller.cacheAccountId!,
        route: invalid == '路线' ? ConnectionMode.webvpn : ConnectionMode.direct,
        fetchedAt: DateTime.utc(2026, 10, 23),
        complete: invalid != '完整度',
        query: invalid == '查询'
            ? const FeatureQuery(
                view: FeatureQueryView.scheduleWeek,
                term: 'selected',
                week: 4,
              )
            : query,
        details: const [FeatureDetail(title: '不可采用的课程')],
      );
      backend.failCache = invalid == '读取失败';
      backend.task.release(finished: true);
      await importing;
      expect(controller.snapshots[FeatureId.schedule], same(previous));
      expect(
        controller.scheduleImports['selected']!.status,
        ScheduleImportStatus.saved,
      );
    });
  }

  test('缓存回读期间切周，迟到导入投影不能覆盖新查询', () async {
    final backend = _Backend();
    final controller = await setup(backend);
    const query = FeatureQuery(
      view: FeatureQueryView.scheduleWeek,
      term: 'selected',
      week: 3,
    );
    await controller.refreshFeatureQuery(FeatureId.schedule, query);
    final importing = controller.saveScheduleSemester('selected');
    await until(() => backend.task.pending.isNotEmpty);
    final read = Completer<OfflineQueryRead>();
    backend.pendingCache = read;
    backend.cachePolicies.clear();
    backend.task.release(finished: true);
    await until(() => backend.cachePolicies.isNotEmpty);
    backend.pendingCache = null;
    const next = FeatureQuery(
      view: FeatureQueryView.scheduleWeek,
      term: 'selected',
      week: 4,
    );
    await controller.refreshFeatureQuery(FeatureId.schedule, next);
    final current = controller.snapshots[FeatureId.schedule];
    read.complete(
      OfflineQueryRead(
        CachedFeatureProjection(
          feature: FeatureId.schedule,
          accountId: controller.cacheAccountId!,
          route: ConnectionMode.direct,
          fetchedAt: DateTime.utc(2026, 10, 23),
          complete: true,
          query: query,
          details: const [FeatureDetail(title: '迟到课程')],
        ),
      ),
    );
    await importing;
    expect(controller.snapshots[FeatureId.schedule], same(current));
  });

  test('后台及待确认写意图暂停下一批，恢复后继续且不自动提交', () async {
    final backend = _Backend();
    final controller = await setup(backend);
    final importing = controller.saveScheduleSemester('selected');
    await until(() => backend.task.pending.isNotEmpty);
    controller.setAppForeground(false);
    backend.task.release(finished: false);
    await Future<void>.delayed(Duration.zero);
    expect(backend.task.calls, 1);
    controller.setAppForeground(true);
    controller.writeCoordinator.setIntent(
      WriteIntent(
        intentId: 'synthetic',
        operation: WriteOperation.bykcSelectCourse,
        targetSummary: '合成目标',
        resolvedRoute: ConnectionMode.direct,
        warnings: const [],
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        requestDigest: 'synthetic',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(backend.task.calls, 1);
    expect(controller.writeCoordinator.intent?.intentId, 'synthetic');
    await controller.writeCoordinator.cancel();
    await until(() => backend.task.pending.isNotEmpty);
    backend.task.release(finished: true);
    await importing;
    expect(
      controller.scheduleImports['selected']!.status,
      ScheduleImportStatus.saved,
    );
  });
  test('取消在途导入不交付迟到成功，显式重试可开始新计划', () async {
    final backend = _Backend();
    final controller = await setup(backend);
    final old = controller.saveScheduleSemester('selected');
    await until(() => backend.task.pending.isNotEmpty);
    controller.cancelScheduleImport('selected');
    backend.task.release(finished: true);
    await old;
    expect(
      controller.scheduleImports['selected']!.status,
      ScheduleImportStatus.cancelled,
    );
    final retry = controller.saveScheduleSemester('selected');
    await until(() => backend.task.pending.isNotEmpty);
    backend.task.release(
      finished: true,
      failure: CacheMaintenanceFailure.capacity,
    );
    await retry;
    expect(
      controller.scheduleImports['selected']!.status,
      ScheduleImportStatus.failed,
    );
    expect(controller.scheduleImports['selected']!.progress!.saved, isFalse);
    expect(backend.events.where((e) => e == 'begin').length, 2);
  });
  test('首页刷新不取消固定学期，显式清理拒绝随后到达的保存结果', () async {
    final backend = _Backend();
    final controller = await setup(backend);
    final pending = controller.saveScheduleSemester('selected');
    await until(() => backend.task.pending.isNotEmpty);
    final refresh = controller.refreshHome();
    expect(backend.task.cancelled, isFalse);
    await controller.clearBusinessCache(accountId: controller.cacheAccountId!);
    expect(backend.task.cancelled, isTrue);
    backend.task.release(finished: true);
    await Future.wait([pending, refresh]);
    expect(controller.scheduleImports, isEmpty);
    expect(controller.phase, AppPhase.home);
    expect(backend.clears, 1);
  });
  test('普通失败保留当前页面且不重发，明确账号冲突关闭旧身份', () async {
    for (final mismatch in [false, true]) {
      final backend = _Backend();
      final controller = await setup(backend);
      final pending = controller.saveScheduleSemester('selected');
      await until(() => backend.task.pending.isNotEmpty);
      backend.task.pending
          .removeAt(0)
          .completeError(
            BackendException(
              mismatch
                  ? UbaaErrorCode.authenticationRequired
                  : UbaaErrorCode.networkError,
              accountMismatch: mismatch,
            ),
          );
      await pending;
      expect(backend.task.calls, 1);
      expect(controller.phase, mismatch ? AppPhase.login : AppPhase.home);
      if (mismatch) {
        expect(controller.scheduleImports, isEmpty);
      } else {
        expect(
          controller.scheduleImports['selected']!.error?.code,
          UbaaErrorCode.networkError,
        );
        expect(
          controller.scheduleImports['selected']!.status,
          ScheduleImportStatus.failed,
        );
      }
    }
  });
  test('路线切换与退出取消在途任务，不残留旧账号状态', () async {
    final backend = _Backend();
    final controller = await setup(backend);
    final old = controller.saveScheduleSemester('selected');
    await until(() => backend.task.pending.isNotEmpty);
    await controller.setRoutePolicy(RoutePolicy.webvpn);
    expect(backend.task.cancelled, isTrue);
    backend.task.release(finished: true);
    await old;
    expect(controller.scheduleImports, isEmpty);
    final second = controller.saveScheduleSemester('selected');
    await until(() => backend.task.pending.isNotEmpty);
    await controller.logout();
    backend.task.release(finished: true);
    await second;
    expect(controller.scheduleImports, isEmpty);
  });
}

class _Backend extends support.FakeRecoveryBackend
    implements
        ScheduleImportBackend,
        OfflineQueryBackend,
        ProgressiveReadBackend,
        FeatureQueryBackend,
        WriteCommitBackend,
        CacheManagementBackend {
  @override
  Future<void> discardWriteIntent(String intentId) async {}
  @override
  Future<WriteCommitResult> commitWrite(String intentId) =>
      throw StateError('导入不能提交学校写入');
  int clears = 0;
  @override
  Future<CacheUsageSummary> cacheUsage({required String accountId}) =>
      throw StateError('此用例不读取容量');
  @override
  Future<CacheClearOutcome> clearBusinessCache({
    required String accountId,
  }) async {
    clears++;
    return const CacheClearOutcome(compacted: true);
  }

  bool failCache = false;
  CachedFeatureProjection? cached;
  Completer<OfflineQueryRead>? pendingCache;
  final cachePolicies = <RoutePolicy>[];
  @override
  Future<OfflineQueryRead> readCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    RoutePolicy policy,
  ) async {
    cachePolicies.add(policy);
    if (failCache) throw const BackendException(UbaaErrorCode.networkError);
    return pendingCache?.future ?? OfflineQueryRead(cached);
  }

  final events = <String>[];
  late final task = _Task(events);
  @override
  Future<ScheduleImportTask> beginScheduleImport(String term) async {
    events.add('begin');
    task.cancelled = false;
    return task;
  }

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    events.add(feature.name);
    return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
  }
}

class _Task implements ScheduleImportTask {
  _Task(this.events);
  final List<String> events;
  final pending = <Completer<ScheduleImportProgress>>[];
  int calls = 0;
  bool cancelled = false;
  @override
  Future<ScheduleImportProgress> next() {
    calls++;
    events.add('batch');
    final c = Completer<ScheduleImportProgress>();
    pending.add(c);
    return c.future;
  }

  void release({required bool finished, CacheMaintenanceFailure? failure}) =>
      pending
          .removeAt(0)
          .complete(
            ScheduleImportProgress(
              term: 'selected',
              completedWeeks: finished ? 2 : 1,
              totalWeeks: 2,
              finished: finished,
              route: ConnectionMode.direct,
              saveFailure: failure,
            ),
          );
  @override
  void cancel() => cancelled = true;
}

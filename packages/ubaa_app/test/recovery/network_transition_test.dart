import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import '../support/controller/clock_accounts.dart';

Future<AppController> start(_Backend backend) async {
  final controller = AppController(
    backend: backend,
    localAccountStore: ClockAccounts(),
  );
  await controller.initialize();
  await controller.recoverSession(refreshHomeAfter: false);
  controller.onHomeFirstFrame();
  return controller;
}

void main() {
  testWidgets('换网前已完成但迟到交付的查询结果必须重读', (tester) async {
    final backend = _LateBackend();
    final controller = await start(backend);
    addTearDown(controller.dispose);
    const query = FeatureQuery(term: 'synthetic-term', week: 7);
    backend.block = true;
    final reading = controller.refreshFeatureQuery(FeatureId.schedule, query);
    await tester.pump();
    controller.onNetworkChanged();
    await tester.pump();
    backend.block = false;
    backend.route = ConnectionMode.webvpn;
    backend.pending!.complete(
      FeatureResult.success(
        summary: '旧网络结果',
        details: const [FeatureDetail(title: '旧网络结果')],
      ),
    );
    await tester.pumpAndSettle();
    await reading;
    expect(
      controller.snapshots[FeatureId.schedule]!.details.single.title,
      '换网后课表',
    );
    expect(backend.queries.length, 2);
    controller.dispose();
  });

  testWidgets('财务服务丢弃旧网络迟到结果并在新网络继续查询', (tester) async {
    final backend = _FinanceBackend();
    final controller = await start(backend);
    addTearDown(controller.dispose);
    final reading = controller.financeService!.refresh();
    await tester.pump();
    controller.onNetworkChanged();
    await tester.pump();
    backend.response.complete(backend.snapshot('旧结果'));
    await tester.pumpAndSettle();
    final result = await reading;
    expect(result.entries.single.id, '新结果');
    expect(backend.reads, 2);
    controller.dispose();
  });

  testWidgets('手动切换取消旧读取并在同一页面重新读取原查询', (tester) async {
    final backend = _ManualBackend();
    final controller = await start(backend);
    addTearDown(controller.dispose);
    const query = FeatureQuery(term: 'synthetic-term', week: 5);
    await controller.refreshFeatureQuery(FeatureId.schedule, query);
    backend.block = true;
    final old = controller.refreshFeatureQuery(FeatureId.schedule, query);
    await tester.pump();
    await controller.setRoutePolicy(RoutePolicy.webvpn);
    await tester.pumpAndSettle();
    await old;
    expect(controller.phase, AppPhase.home);
    expect(controller.loginForm.routePolicy, RoutePolicy.webvpn);
    expect(
      controller.snapshots[FeatureId.schedule]!.details.single.title,
      '换网后课表',
    );
    expect(backend.queries.map((q) => (q.term, q.week)), [
      (query.term, query.week),
      (query.term, query.week),
      (query.term, query.week),
    ]);
    expect(backend.cancellations, 1);
    controller.dispose();
  });

  testWidgets('写入已发送后换网保留原结果且只提交一次', (tester) async {
    final backend = _WriteBackend();
    final controller = await start(backend);
    addTearDown(controller.dispose);
    controller.writeCoordinator.setIntent(
      WriteIntent(
        intentId: 'synthetic-intent',
        operation: WriteOperation.bykcSelectCourse,
        targetSummary: '合成课程',
        resolvedRoute: ConnectionMode.direct,
        warnings: const [],
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        requestDigest: 'synthetic',
      ),
    );
    final writing = controller.writeCoordinator.confirmForUi();
    await tester.pump();
    expect(backend.commits, 1);
    controller.onNetworkChanged();
    await tester.pump();
    expect(controller.writeCoordinator.state.phase, WritePhase.committing);
    backend.release.complete(
      const WriteCommitResult(
        operation: WriteOperation.bykcSelectCourse,
        success: true,
        outcomeUnknown: false,
        message: '合成成功',
      ),
    );
    await tester.pumpAndSettle();
    final outcome = await writing;
    expect(outcome?.result?.operation, WriteOperation.bykcSelectCourse);
    expect(backend.commits, 1);
    controller.dispose();
  });
  testWidgets('校园网读取中断开并恢复联网后保留页面与查询且自动重读', (tester) async {
    final backend = _Backend();
    final controller = await start(backend);
    addTearDown(controller.dispose);
    const query = FeatureQuery(term: 'synthetic-term', week: 4);
    await controller.refreshFeatureQuery(FeatureId.schedule, query);
    backend.block = true;
    final pending = controller.refreshFeatureQuery(FeatureId.schedule, query);
    await tester.pump();
    expect(backend.pending, isNotNull);
    controller.onNetworkChanged(online: false);
    await tester.pump();
    expect(controller.networkOnline, isFalse);
    expect(controller.phase, AppPhase.home);
    expect(
      controller.snapshots[FeatureId.schedule]!.details.single.title,
      '已显示课表',
    );
    backend.block = false;
    backend.route = ConnectionMode.webvpn;
    controller.onNetworkChanged();
    await tester.pumpAndSettle();
    await pending;
    expect(controller.phase, AppPhase.home);
    expect(controller.snapshots[FeatureId.schedule]!.error, isNull);
    expect(
      controller.snapshots[FeatureId.schedule]!.details.single.title,
      '换网后课表',
    );
    expect(backend.queries.map((value) => (value.term, value.week)), [
      (query.term, query.week),
      (query.term, query.week),
      (query.term, query.week),
    ]);
    expect(backend.targets, contains(RecoveryTarget.connection));
    expect(backend.cancellations, 1);
    controller.dispose();
  });

  testWidgets('连续换网采用最后一次观察且旧观察不能覆盖新网络', (tester) async {
    final backend = _Backend()..pauseInspect = true;
    final controller = await start(backend);
    addTearDown(controller.dispose);
    controller.onNetworkChanged();
    await tester.pump();
    final old = backend.operations.single;
    controller.onNetworkChanged();
    await tester.pump();
    final latest = backend.operations.last;
    expect(backend.operations.length, 2);
    latest.gate.complete(BackendNetworkState.campus);
    await tester.pumpAndSettle();
    expect(
      backend.targets.where((v) => v == RecoveryTarget.connection).length,
      1,
    );
    old.gate.complete(BackendNetworkState.offCampus);
    await tester.pumpAndSettle();
    expect(
      backend.targets.where((v) => v == RecoveryTarget.connection).length,
      1,
    );
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
    controller.dispose();
  });

  testWidgets('恢复期限包含探测等待且超时后手动重试可以恢复', (tester) async {
    final backend = _Backend()..pauseInspect = true;
    final controller = await start(backend);
    addTearDown(controller.dispose);
    controller.onNetworkChanged();
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    expect(controller.phase, AppPhase.home);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.unavailable);
    expect(backend.operations.single.cancelled, isTrue);
    expect(
      backend.targets.where((v) => v == RecoveryTarget.connection),
      isEmpty,
    );
    backend.operations.single.gate.complete(BackendNetworkState.offCampus);
    await tester.pumpAndSettle();
    expect(
      backend.targets.where((v) => v == RecoveryTarget.connection),
      isEmpty,
    );
    await controller.recoverSession();
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
    controller.dispose();
  });
}

class _Operation implements NetworkChangeOperation {
  _Operation(this.paused);
  final bool paused;
  final gate = Completer<BackendNetworkState>();
  bool cancelled = false;
  @override
  Future<BackendNetworkState> inspect() =>
      paused ? gate.future : Future.value(BackendNetworkState.offCampus);
  @override
  void finish() {}
  @override
  void cancel() {
    cancelled = true;
  }
}

class _Backend extends support.FakeRecoveryBackend
    implements
        NetworkChangeBackend,
        RequiredTargetSessionBackend,
        ProgressiveReadBackend,
        FeatureQueryBackend {
  bool block = false, pauseInspect = false;
  int cancellations = 0;
  ConnectionMode route = ConnectionMode.direct;
  Completer<FeatureResult>? pending;
  final operations = <_Operation>[];
  final queries = <FeatureQuery>[];
  final targets = <RecoveryTarget>[];
  @override
  NetworkChangeOperation beginNetworkChange({
    required bool online,
    required Duration budget,
  }) {
    cancelNetworkReads();
    final operation = _Operation(pauseInspect);
    operations.add(operation);
    return operation;
  }

  @override
  void cancelNetworkReads() {
    if (pending case final read? when !read.isCompleted) {
      cancellations++;
      read.completeError(
        const BackendException(UbaaErrorCode.networkError, retryable: false),
      );
    }
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
  ) {
    queries.add(query);
    if (block) return (pending = Completer<FeatureResult>()).future;
    return Future.value(
      FeatureResult.success(
        summary: '合成课表',
        resolvedRoute: route,
        details: [
          FeatureDetail(
            title: route == ConnectionMode.direct ? '已显示课表' : '换网后课表',
          ),
        ],
      ),
    );
  }

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(FeatureId feature) =>
      recoverTargetSession(RecoveryTarget.fromFeature(feature));
  @override
  Future<RecoveredRouteSession> recoverTargetSession(
    RecoveryTarget target,
  ) async {
    targets.add(target);
    return RecoveredRouteSession(route: route, profile: (await userInfo())!);
  }

  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) async => throw StateError('合成会话无需提交凭据');
}

class _ManualBackend extends _Backend
    implements RoutePolicyBackend, RouteSettingsBackend {
  RoutePolicy policy = RoutePolicy.auto;
  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: policy,
    activeRoutes: ConnectionMode.values,
  );
  @override
  Future<BackendRouteSettings> setDefaultRoutePolicy(RoutePolicy value) async {
    policy = value;
    route = ConnectionMode.webvpn;
    block = false;
    return routeSettings();
  }
}

class _LateBackend extends _Backend {
  @override
  void cancelNetworkReads() {}
}

class _FinanceBackend extends _Backend
    implements FinanceBackend, FinanceService {
  final response = Completer<FinanceSnapshot>();
  int reads = 0;
  @override
  FinanceService get finance => this;
  @override
  Future<FinanceSnapshot?> cached() async => null;
  FinanceSnapshot snapshot(String id) => FinanceSnapshot(
    entries: [FinanceIncome(id: id)],
    total: 1,
    route: ConnectionMode.webvpn,
    fetchedAt: DateTime.utc(2026),
    fromCache: false,
    savedForOffline: false,
  );
  @override
  Future<FinanceSnapshot> refresh() =>
      ++reads == 1 ? response.future : Future.value(snapshot('新结果'));
}

class _WriteBackend extends _Backend implements WriteCommitBackend {
  int commits = 0;
  final release = Completer<WriteCommitResult>();
  @override
  Future<WriteCommitResult> commitWrite(String intentId) {
    commits++;
    return release.future;
  }

  @override
  Future<void> discardWriteIntent(String intentId) async {}
}

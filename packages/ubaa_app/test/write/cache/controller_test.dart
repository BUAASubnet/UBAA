import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../recovery/startup_test.dart' as support;
import '../../cache/query_test.dart' show until;

const _query = FeatureQuery(view: FeatureQueryView.bykcDetail, courseId: '42');
void main() {
  Future<AppController> setup(SyntheticWriteCacheBackend backend) async {
    final accounts = await support.savedAccounts();
    backend.expectedAccount = (await accounts.read())!.account!.id;
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(refreshHomeAfter: false);
    await controller.refreshFeatureQuery(FeatureId.bykc, _query);
    await controller.refreshFeatureQuery(
      FeatureId.schedule,
      const FeatureQuery(
        view: FeatureQueryView.scheduleWeek,
        term: 'term',
        week: 1,
      ),
    );
    return controller;
  }

  test('提交使用原本机账号且在既定回读前撤下旧动作，后台暂停后续普通刷新', () async {
    final backend = SyntheticWriteCacheBackend();
    final controller = await setup(backend);
    final unrelated = controller.snapshots[FeatureId.schedule];
    controller.writeCoordinator.setIntent(_intent());
    final confirming = controller.writeCoordinator.confirmForUi();
    await until(() => backend.readbacks == 1);
    expect(backend.cachedCommits, 1);
    expect(backend.ordinaryCommits, 0);
    expect(backend.account, backend.expectedAccount);
    expect(
      controller.snapshots[FeatureId.bykc]!.details.single.actions,
      isEmpty,
    );
    expect(
      controller.snapshots[FeatureId.bykc]!.readContext!.hasSameQuery(_query),
      isTrue,
    );
    expect(controller.snapshots[FeatureId.schedule], same(unrelated));
    controller.setAppForeground(false);
    backend.readback.complete(
      const FeatureResult.empty(resolvedRoute: ConnectionMode.direct),
    );
    final outcome = await confirming;
    expect(outcome!.result!.success, isTrue);
    expect(backend.postCommitQueries, 0);
    controller.setAppForeground(true);
    await until(() => backend.postCommitQueries > 0);
    expect(backend.cachedCommits, 1);
    expect(
      controller.snapshots[FeatureId.bykc]!.readContext!.hasSameQuery(_query),
      isTrue,
    );
  });
  test('学校确定失败不失效旧内容或自动补发，回读失败不降级已成功提交', () async {
    final rejected = SyntheticWriteCacheBackend()..success = false;
    final first = await setup(rejected);
    final old = first.snapshots[FeatureId.bykc];
    first.writeCoordinator.setIntent(_intent());
    final failure = await first.writeCoordinator.confirmForUi();
    expect(failure!.result!.success, isFalse);
    expect(first.snapshots[FeatureId.bykc], same(old));
    expect(rejected.readbacks, 0);
    expect(rejected.postCommitQueries, 0);

    final backend = SyntheticWriteCacheBackend()..failRefresh = true;
    final controller = await setup(backend);
    controller.writeCoordinator.setIntent(_intent());
    final confirming = controller.writeCoordinator.confirmForUi();
    await until(() => backend.readbacks == 1);
    backend.readback.completeError(
      const BackendException(UbaaErrorCode.networkError),
    );
    final result = await confirming;
    expect(result!.result!.success, isTrue);
    await until(
      () =>
          controller.snapshots[FeatureId.bykc]!.error?.code ==
          UbaaErrorCode.networkError,
    );
    expect(
      controller.snapshots[FeatureId.bykc]!.details.single.actions,
      isEmpty,
    );
    expect(backend.cachedCommits, 1);
  });
  test('提交期间注销，迟到本地警告和后续刷新不能进入新登录页', () async {
    final backend = SyntheticWriteCacheBackend()
      ..commitGate = Completer<WriteCommitResult>();
    final controller = await setup(backend);
    controller.writeCoordinator.setIntent(_intent());
    final confirming = controller.writeCoordinator.confirmForUi();
    await until(() => backend.cachedCommits == 1);
    await controller.logout();
    backend.commitGate!.complete(
      const WriteCommitResult(
        operation: WriteOperation.bykcSelectCourse,
        success: true,
        message: '合成成功',
        outcomeUnknown: false,
        resolvedRoute: ConnectionMode.direct,
        cacheFailure: CacheMaintenanceFailure.capacity,
      ),
    );
    expect(await confirming, isNull);
    expect(controller.phase, AppPhase.login);
    expect(controller.localCacheError, isNull);
    expect(backend.postCommitQueries, 0);
    expect(backend.readbacks, 0);
  });
  test('未知结果保留学校错误与本地警告，回读和后续刷新都不再次提交', () async {
    final backend = SyntheticWriteCacheBackend()..unknown = true;
    final controller = await setup(backend);
    controller.setAppForeground(false);
    controller.writeCoordinator.setIntent(_intent());
    final confirming = controller.writeCoordinator.confirmForUi();
    await until(() => backend.readbacks == 1);
    backend.readback.complete(
      const FeatureResult.empty(resolvedRoute: ConnectionMode.direct),
    );
    final outcome = await confirming;
    expect(outcome!.error?.code, UbaaErrorCode.outcomeUnknown);
    expect(controller.localCacheError, isNotNull);
    expect(backend.cachedCommits, 1);
    controller.setAppForeground(true);
    await until(() => backend.postCommitQueries > 0);
    expect(backend.cachedCommits, 1);
    expect(backend.ordinaryCommits, 0);
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

class SyntheticWriteCacheBackend extends support.FakeRecoveryBackend
    implements
        CacheWriteBackend,
        BykcWriteBackend,
        ProgressiveReadBackend,
        FeatureQueryBackend,
        BykcReadbackBackend {
  int prepares = 0;
  @override
  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) async {
    if (courseId != 42)
      throw const BackendException(UbaaErrorCode.invalidInput);
    prepares++;
    return _intent();
  }

  @override
  Future<WriteIntent> prepareBykcDeselectCourse({
    required int courseId,
  }) async => throw const BackendException(UbaaErrorCode.unsupported);
  @override
  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) async => throw const BackendException(UbaaErrorCode.unsupported);
  int cachedCommits = 0,
      ordinaryCommits = 0,
      readbacks = 0,
      postCommitQueries = 0;
  bool unknown = false, success = true, failRefresh = false;
  Completer<WriteCommitResult>? commitGate;
  String? account, expectedAccount;
  final readback = Completer<FeatureResult>();
  @override
  Future<void> discardWriteIntent(String intentId) async {}
  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    ordinaryCommits++;
    return _result;
  }

  @override
  Future<WriteCommitResult> commitWriteWithCache(
    String intentId, {
    required String accountId,
  }) async {
    cachedCommits++;
    account = accountId;
    if (commitGate case final gate?) return gate.future;
    if (unknown)
      throw const BackendException(
        UbaaErrorCode.outcomeUnknown,
        resolvedRoute: ConnectionMode.direct,
        cacheFailure: CacheMaintenanceFailure.corrupt,
      );
    return _result;
  }

  WriteCommitResult get _result => WriteCommitResult(
    operation: WriteOperation.bykcSelectCourse,
    success: success,
    message: '合成成功',
    outcomeUnknown: false,
    resolvedRoute: ConnectionMode.direct,
  );
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) =>
      feature == FeatureId.bykc
      ? loadFeatureQuery(feature, const FeatureQuery())
      : super.loadFeature(feature);

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;
  @override
  Future<FeatureResult> readBykcAfterWrite(FeatureQuery query) {
    readbacks++;
    return readback.future;
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (cachedCommits + ordinaryCommits > 0) postCommitQueries++;
    if (postCommitQueries > 0 && failRefresh)
      throw const BackendException(UbaaErrorCode.networkError);
    return FeatureResult.success(
      resolvedRoute: ConnectionMode.direct,
      details: [
        FeatureDetail(
          title: feature == FeatureId.bykc ? '合成课程' : '无关课表',
          fields: feature == FeatureId.bykc
              ? const [FeatureField(label: '课程 ID', value: '42')]
              : const [],
          actions: feature == FeatureId.bykc
              ? const [
                  BykcSelectAction(
                    courseId: 42,
                    eligibility: ActionEligibility.allowed,
                  ),
                ]
              : const [],
        ),
      ],
    );
  }
}

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import '../../recovery/backend_rebuild/fakes.dart' as base;

void main() {
  late _Backend backend;
  late AppController controller;
  late GradeScoreWatch watch;
  setUp(() async {
    backend = _Backend();
    controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    await base.cachedHome(controller, backend);
    await controller.recoverSession(refreshHomeAfter: false);
    watch = GradeScoreWatch(
      controller: controller,
      store: ControllerGradeScoreStore(controller),
    );
  });
  tearDown(() {
    watch.dispose();
    controller.dispose();
  });
  test('完整在线成绩经账号加密通道建立和比较基线，缓存观察不重复更新', () async {
    await watch.check();
    expect(backend.updates, 1);
    expect(backend.lastAccount, backend.account!.id);
    expect(watch.notice, isNull);
    backend.score = '90';
    await watch.check(forceRefresh: true);
    expect(watch.notice!.changes.single.oldScore, '80');
    expect(watch.notice!.changes.single.newScore, '90');
    backend.persisted = true;
    backend.score = '100';
    await watch.check(forceRefresh: true);
    expect(backend.updates, 2);
    expect(watch.notice!.changes.single.newScore, '90');
  });
  test('密钥或容量故障与学校成功分列，不更新基线且不写明文', () async {
    backend.failure = const BackendException(
      UbaaErrorCode.internalError,
      cacheFailure: CacheMaintenanceFailure.unavailable,
    );
    await watch.check();
    expect(watch.error, isNull);
    expect(watch.cacheError, isNotNull);
    expect(watch.checkedRoute, ConnectionMode.direct);
    expect((await controller.loadGradeTerm(term)).overview, isNotNull);
    expect(backend.values, isEmpty);
    backend.failure = null;
    await watch.check(forceRefresh: true);
    expect(watch.cacheError, isNull);
    expect(watch.notice, isNull);
  });
  test('退出使迟到本地观察失效', () async {
    backend.updateGate = Completer<void>();
    final checking = watch.check();
    await backend.updateStarted.future;
    await controller.logout();
    backend.updateGate!.complete();
    await checking;
    expect(watch.notice, isNull);
    expect(watch.cacheError, isNull);
    expect(backend.values, isEmpty);
  });
  test('显式清理加密基线和变化提醒', () async {
    await watch.check();
    backend.score = '90';
    await watch.check(forceRefresh: true);
    expect(watch.notice, isNotNull);
    await controller.clearBusinessCache(accountId: controller.cacheAccountId!);
    expect(backend.clears, 1);
    expect(controller.isClearingBusinessCache, isFalse);
    expect(backend.values, isEmpty);
    expect(watch.notice, isNull);
    expect(controller.phase, AppPhase.home);
  });
  test('清理后拒绝在途批次迟到交付', () async {
    backend.updateGate = Completer<void>();
    final pending = watch.check();
    await backend.updateStarted.future;
    final clearing = controller.clearBusinessCache(
      accountId: controller.cacheAccountId!,
    );
    await clearing;
    expect(controller.isClearingBusinessCache, isFalse);
    backend.updateGate!.complete();
    await pending;
    expect(backend.values, isEmpty);
    expect(watch.notice, isNull);
    expect(watch.cacheError, isNull);
  });
}

const term = '2026-2027-1';

class _Backend extends base.Backend
    implements
        FeatureQueryBackend,
        GradeScoreBaselineBackend,
        CacheManagementBackend {
  String score = '80';
  bool persisted = false;
  int updates = 0, generation = 0, clears = 0;
  String? lastAccount;
  BackendException? failure;
  Completer<void>? updateGate;
  final updateStarted = Completer<void>();
  final values = <(ConnectionMode, String), GradeScoreBaseline>{};
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (query.view == FeatureQueryView.gradesTerms)
      return const FeatureResult.success(
        details: [
          FeatureDetail(
            title: '合成学期',
            presentation: TermPresentation(
              code: term,
              selected: true,
              index: 0,
            ),
          ),
        ],
        resolvedRoute: ConnectionMode.direct,
      );
    if (feature == FeatureId.grades)
      return FeatureResult.success(
        overview: GradesTermOverview(
          requestTerm: term,
          termCode: term,
          grades: [
            GradePresentation(
              courseName: '合成课程',
              courseCode: 'safe',
              score: score,
            ),
          ],
        ),
        resolvedRoute: ConnectionMode.direct,
        evidence: persisted
            ? DataEvidence(
                accountId: account!.id,
                origin: DataOrigin.persisted,
                fetchedAt: DateTime.utc(2026),
                complete: true,
                savedForOffline: true,
              )
            : null,
      );
    return const FeatureResult.empty();
  }

  @override
  Future<GradeScoreBaseline?> updateGradeScoreBaseline({
    required String accountId,
    required ConnectionMode route,
    required GradeScoreBaseline latest,
    GradeScoreBaseline? legacy,
  }) async {
    updates++;
    lastAccount = accountId;
    final epoch = generation;
    if (!updateStarted.isCompleted) updateStarted.complete();
    await updateGate?.future;
    if (epoch != generation)
      throw const BackendException(UbaaErrorCode.operationConflict);
    if (failure case final error?) throw error;
    expect(legacy, isNull);
    final previous = values[(route, latest.termCode)];
    values[(route, latest.termCode)] = latest;
    return previous;
  }

  @override
  Future<void> deactivateOfflineAccount() async {
    generation++;
  }

  @override
  Future<CacheClearOutcome> clearBusinessCache({
    required String accountId,
  }) async {
    clears++;
    generation++;
    values.clear();
    return const CacheClearOutcome(compacted: true);
  }

  @override
  Future<CacheUsageSummary> cacheUsage({required String accountId}) =>
      throw UnimplementedError();
}

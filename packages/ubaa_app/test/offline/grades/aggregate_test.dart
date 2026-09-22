import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../startup_test.dart' as support;
import '../query_cache_test.dart' show until;

void main() {
  test('在线学期索引不完整时统计不能冒充全量', () async {
    final backend = GradesBackend()
      ..online = true
      ..partialIndex = true;
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(refreshHomeAfter: false);
    final result = await controller.loadAllGrades();
    expect(result.loadedTerms, 2);
    expect(result.isComplete, isFalse);
    expect(result.termsEvidence!.complete, isFalse);
  });

  test('一条磁盘读取损坏不丢其他学期，部分索引不声称完整', () async {
    final backend = GradesBackend()
      ..broken = 'b'
      ..partialIndex = true;
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    GradesAggregate? local;
    final pending = controller.loadAllGrades(
      onProgress: (value) => local = value,
    );
    await until(() => local != null);
    expect(local!.loadedTerms, 1);
    expect(local!.isComplete, isFalse);
    expect(local!.termsEvidence!.complete, isFalse);
    controller.onHomeFirstFrame();
    expect((await pending).loadedTerms, 1);
  });

  for (final mismatch in ['账号', '学期', '路线']) {
    test('$mismatch不匹配的缓存不进入统计', () async {
      final backend = GradesBackend()..mismatch = mismatch;
      final controller = AppController(
        backend: backend,
        localAccountStore: await support.savedAccounts(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      if (mismatch == '路线') await controller.setRoutePolicy(RoutePolicy.direct);
      GradesAggregate? local;
      final pending = controller.loadAllGrades(
        onProgress: (value) => local = value,
      );
      await until(() => local != null);
      expect(local!.loadedTerms, 0);
      expect(local!.isComplete, isFalse);
      controller.onHomeFirstFrame();
      await pending;
    });
  }

  test('退出后迟到缓存和在线结果均不交付', () async {
    final backend = GradesBackend()..diskGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final progress = <GradesAggregate>[];
    final pending = controller.loadAllGrades(onProgress: progress.add);
    await controller.logout();
    backend.diskGate!.complete();
    expect((await pending).error?.code, UbaaErrorCode.operationConflict);
    await Future<void>.delayed(Duration.zero);
    expect(progress, isEmpty);
  });

  test('首帧认证前渐进交付跨学期缓存，缺学期不冒充完整', () async {
    final backend = GradesBackend()..missing = 'b';
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    GradesAggregate? local;
    final pending = controller.loadAllGrades(
      onProgress: (value) => local = value,
    );
    await until(() => local != null);
    expect(local!.loadedTerms, 1);
    expect(local!.isComplete, isFalse);
    expect(local!.statistics.weightedAverage, 80);
    expect(local!.terms.first.result.evidence!.fetchedAt, backend.fetched);
    expect(backend.authCalls, 0);
    controller.onHomeFirstFrame();
    final finalValue = await pending;
    expect(finalValue.loadedTerms, 1);
    expect(finalValue.error, isNotNull);
    expect(
      finalValue.terms.first.result.evidence!.origin,
      DataOrigin.persisted,
    );
  });

  test('在线成功替换先返回的历史统计，完整刷新也保留缓存可读', () async {
    final backend = GradesBackend()..online = true;
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    GradesAggregate? local;
    final pending = controller.loadAllGrades(
      forceRefresh: true,
      onProgress: (value) => local = value,
    );
    await until(() => local != null);
    expect(local!.statistics.weightedAverage, 80);
    await controller.recoverSession(refreshHomeAfter: false);
    final value = await pending;
    expect(value.error, isNull);
    expect(value.statistics.weightedAverage, 95);
    expect(value.terms.every((t) => t.result.evidence == null), isTrue);
    expect(value.isComplete, isTrue);
  });

  test('迟到缓存不得覆盖已完成在线结果', () async {
    final backend = GradesBackend()
      ..online = true
      ..diskGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final progress = <GradesAggregate>[];
    final pending = controller.loadAllGrades(onProgress: progress.add);
    await controller.recoverSession(refreshHomeAfter: false);
    final value = await pending;
    expect(value.error, isNull);
    expect(value.statistics.weightedAverage, 95);
    backend.diskGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(progress, isEmpty);
  });
}

class GradesBackend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        ProgressiveReadBackend,
        RequiredSessionBackend,
        OfflineCacheBackend,
        OfflineQueryBackend {
  LocalAccount? account;
  bool online = false;
  String? missing, broken, mismatch;
  bool partialIndex = false;
  Completer<void>? diskGate;
  int authCalls = 0;
  final fetched = DateTime.utc(2026, 9, 1);
  @override
  Future<void> openOfflineAccount(LocalAccount value, List<int> key) async {
    account = value;
  }

  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) async =>
      OfflineHomeRead([]);
  List<FeatureDetail> get terms => [
    for (final term in ['a', 'b'])
      FeatureDetail(
        title: '合成学期$term',
        presentation: TermPresentation(
          code: term,
          selected: term == 'a',
          index: 0,
        ),
      ),
  ];
  GradesTermOverview grade(String term, String score) => GradesTermOverview(
    requestTerm: term,
    termCode: term,
    grades: [
      GradePresentation(courseName: '合成课程$term', score: score, credit: 2),
    ],
  );
  @override
  Future<OfflineQueryRead> readCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    RoutePolicy policy,
  ) async {
    await diskGate?.future;
    if (feature == FeatureId.grades && query.term == broken)
      throw const BackendException(UbaaErrorCode.internalError);
    if (feature == FeatureId.grades && query.term == missing)
      return const OfflineQueryRead(null);
    return OfflineQueryRead(
      CachedFeatureProjection(
        feature: feature,
        query: query,
        accountId: feature == FeatureId.grades && mismatch == '账号'
            ? 'other'
            : account!.id,
        route: feature == FeatureId.grades && mismatch == '路线'
            ? ConnectionMode.webvpn
            : ConnectionMode.direct,
        fetchedAt: fetched,
        complete: feature == FeatureId.schedule ? !partialIndex : true,
        details: feature == FeatureId.schedule ? terms : [],
        overview: feature == FeatureId.grades
            ? grade(mismatch == '学期' ? 'other' : query.term!, '80')
            : null,
      ),
    );
  }

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    authCalls++;
    if (!online) throw const BackendException(UbaaErrorCode.networkError);
    return const RecoveredRouteSession(
      route: ConnectionMode.direct,
      profile: UserSummary(username: 'fixture-user'),
    );
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
  ) async => FeatureResult.success(
    details: feature == FeatureId.schedule ? terms : [],
    overview: feature == FeatureId.grades ? grade(query.term!, '95') : null,
    resolvedRoute: ConnectionMode.direct,
    evidence: feature == FeatureId.schedule
        ? DataEvidence(
            accountId: account!.id,
            origin: DataOrigin.online,
            fetchedAt: fetched,
            complete: !partialIndex,
            savedForOffline: true,
          )
        : null,
  );
  @override
  Future<void> logout() async {}
  @override
  Future<void> deactivateOfflineAccount() async {}
  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

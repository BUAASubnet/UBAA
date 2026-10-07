import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../support/controller/grades.dart'
    show FixtureGradesBackend, fixtureGradeTerm;

void _registerGradeWatchTests() {
  test('持久成绩投影不成为出分基线也不触发变化提醒', () async {
    final backend = FixtureGradesBackend()
      ..read = (term) async => FeatureResult.success(
        overview: _watchGrades(term, '90').overview,
        resolvedRoute: ConnectionMode.direct,
        evidence: DataEvidence(
          accountId: 'fixture-student',
          origin: DataOrigin.persisted,
          fetchedAt: DateTime.utc(2026, 9, 1),
          complete: true,
          savedForOffline: true,
        ),
      );
    final controller = AppController(backend: backend);
    final store = MemoryGradeScoreStore();
    final watch = GradeScoreWatch(controller: controller, store: store);
    addTearDown(() {
      watch.dispose();
      controller.dispose();
    });
    await controller.initialize();
    await watch.check();
    expect(await store.read('fixture-student', ConnectionMode.direct), isNull);
    expect(watch.notice, isNull);
  });

  test('首页成绩检查首次建基线，变化提醒保留至查看或忽略', () async {
    var score = '80';
    final backend = FixtureGradesBackend()
      ..read = (term) async => _watchGrades(term, score);
    final controller = AppController(backend: backend);
    final store = MemoryGradeScoreStore();
    final watch = GradeScoreWatch(controller: controller, store: store);
    addTearDown(() {
      watch.dispose();
      controller.dispose();
    });
    await controller.initialize();
    await watch.check();
    expect(watch.notice, isNull);
    expect(
      (await store.read(
        'fixture-student',
        ConnectionMode.direct,
      ))?.scores.single.score,
      '80',
    );
    score = '90';
    await watch.check(forceRefresh: true);
    expect(watch.notice?.changes.single.newScore, '90');
    final notice = watch.notice;
    await watch.check(forceRefresh: true);
    expect(watch.notice, same(notice));
    watch.consumeNotice();
    await watch.check(forceRefresh: true);
    expect(watch.notice, isNull);
  });
  test('成绩空集合和读取失败不覆盖本地基线，首次新实际路线单独建基线', () async {
    final backend = FixtureGradesBackend()
      ..read = (term) async => _watchGrades(term, '80');
    final controller = AppController(backend: backend);
    final store = MemoryGradeScoreStore();
    final watch = GradeScoreWatch(controller: controller, store: store);
    addTearDown(() {
      watch.dispose();
      controller.dispose();
    });
    await controller.initialize();
    await watch.check();
    backend.read = (term) async => fixtureGradeTerm(term, empty: true);
    await watch.check(forceRefresh: true);
    expect(
      (await store.read(
        'fixture-student',
        ConnectionMode.direct,
      ))?.scores.single.score,
      '80',
    );
    backend.read = (_) =>
        throw const BackendException(UbaaErrorCode.networkError);
    await watch.check(forceRefresh: true);
    expect(watch.error?.code, UbaaErrorCode.networkError);
    backend.read = (term) async =>
        _watchGrades(term, '90', route: ConnectionMode.webvpn);
    await watch.check(forceRefresh: true);
    expect(watch.notice, isNull);
    expect(
      (await store.read(
        'fixture-student',
        ConnectionMode.webvpn,
      ))?.scores.single.score,
      '90',
    );
    expect(
      (await store.read(
        'fixture-student',
        ConnectionMode.direct,
      ))?.scores.single.score,
      '80',
    );
  });
  test('成绩检查合并在途，注销后迟到结果不写基线或复活通知', () async {
    final gate = Completer<FeatureResult>();
    final backend = FixtureGradesBackend()..read = (_) => gate.future;
    final controller = AppController(backend: backend);
    final store = MemoryGradeScoreStore();
    final watch = GradeScoreWatch(controller: controller, store: store);
    addTearDown(() {
      watch.dispose();
      controller.dispose();
    });
    await controller.initialize();
    final first = watch.check(), second = watch.check(forceRefresh: true);
    await Future<void>.delayed(Duration.zero);
    expect(backend.gradeCalls, ['a']);
    await controller.logout();
    gate.complete(_watchGrades('a', '90'));
    await Future.wait([first, second]);
    expect(watch.notice, isNull);
    expect(await store.read('fixture-student', ConnectionMode.direct), isNull);
  });

  test('成绩检查完成回调区分完整基线保存与仅缓存结果', () async {
    final backend = FixtureGradesBackend()
      ..read = (term) async => _watchGrades(term, '80');
    final completed = <bool>[];
    final controller = AppController(backend: backend);
    final watch = GradeScoreWatch(
      controller: controller,
      store: MemoryGradeScoreStore(),
      onCheckComplete: completed.add,
    );
    addTearDown(() {
      watch.dispose();
      controller.dispose();
    });
    await controller.initialize();
    await watch.check();
    expect(completed, [true]);
    backend.read = (term) async => FeatureResult.success(
      overview: _watchGrades(term, '80').overview,
      resolvedRoute: ConnectionMode.direct,
      evidence: DataEvidence(
        accountId: 'fixture-student',
        origin: DataOrigin.persisted,
        fetchedAt: DateTime.utc(2026, 9, 1),
        complete: true,
        savedForOffline: true,
      ),
    );
    await watch.check(forceRefresh: true);
    expect(completed, [true, false]);
  });

  test('生命周期竞争取消基线保存时不报告本机保存故障', () async {
    final backend = FixtureGradesBackend()
      ..read = (term) async => _watchGrades(term, '80');
    final controller = AppController(backend: backend);
    final watch = GradeScoreWatch(
      controller: controller,
      store: _OperationConflictGradeStore(),
    );
    addTearDown(() {
      watch.dispose();
      controller.dispose();
    });
    await controller.initialize();
    await watch.check();
    expect(watch.cacheError, isNull);
    expect(watch.error, isNull);
    expect(watch.notice, isNull);
  });
}

final class _OperationConflictGradeStore implements GradeScoreStore {
  @override
  Future<GradeScoreBaseline?> update(
    String account,
    ConnectionMode route,
    GradeScoreBaseline value,
  ) async => throw const BackendException(UbaaErrorCode.operationConflict);

  @override
  Future<void> clearAccount(String account) async {}
}

FeatureResult _watchGrades(
  String term,
  String score, {
  ConnectionMode route = ConnectionMode.direct,
}) => FeatureResult.success(
  overview: GradesTermOverview(
    requestTerm: term,
    termCode: term,
    grades: [
      GradePresentation(courseCode: 'SAFE', courseName: '合成课程', score: score),
    ],
  ),
  resolvedRoute: route,
);

void main() {
  _registerGradeWatchTests();
}

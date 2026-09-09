part of '../app_controller_test.dart';

void _registerGradeWatchTests() {
  test('首页成绩检查首次建基线，变化提醒保留至查看或忽略', () async {
    var score = '80';
    final backend = _GradesBackend()
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
    final backend = _GradesBackend()
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
    backend.read = (term) async => _gradeTerm(term, empty: true);
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
    final backend = _GradesBackend()..read = (_) => gate.future;
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

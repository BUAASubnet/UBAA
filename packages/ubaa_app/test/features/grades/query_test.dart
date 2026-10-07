import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/controller/grades.dart'
    show FixtureGradesBackend, fixtureGradeTerm;

void _registerGradesTests() {
  test('成绩提醒只查唯一当前学期，未选或多个当前不猜首项', () async {
    for (final count in [0, 2, 1]) {
      final backend = FixtureGradesBackend()
        ..termResult = FeatureResult.success(
          details: [
            for (var i = 0; i < 2; i++)
              FeatureDetail(
                title: '合成学期$i',
                presentation: TermPresentation(
                  code: 'term$i',
                  selected: i < count,
                  index: i,
                ),
              ),
          ],
        );
      final controller = AppController(backend: backend);
      await controller.initialize();
      final result = await controller.loadCurrentGrades();
      if (count == 1) {
        expect(result?.code, 'term0');
        expect(backend.gradeCalls, ['term0']);
      } else {
        expect(result, isNull);
        expect(backend.gradeCalls, isEmpty);
      }
      controller.dispose();
    }
  });
  test('成绩明确刷新后聚合复用本次结果，抛错后换视图不复活旧缓存', () async {
    final backend = FixtureGradesBackend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.loadAllGrades();
    const current = FeatureQuery(term: 'b');
    await controller.refreshFeatureQuery(FeatureId.grades, current);
    await controller.refreshFeatureQuery(FeatureId.grades, current);
    expect(backend.gradeCalls, ['a', 'b', 'b']);
    await controller.loadAllGrades(forceRefresh: true);
    expect(backend.gradeCalls, ['a', 'b', 'b', 'a']);
    backend.read = (_) =>
        throw const BackendException(UbaaErrorCode.networkError);
    await controller.refreshFeatureQuery(FeatureId.grades, current);
    expect(
      controller.snapshots[FeatureId.grades]!.status,
      FeatureLoadStatus.stale,
    );
    await controller.refreshFeatureQuery(
      FeatureId.grades,
      const FeatureQuery(term: 'b', view: FeatureQueryView.gradesMissing),
    );
    expect(backend.gradeCalls, ['a', 'b', 'b', 'a', 'b', 'b']);
    expect(
      controller.snapshots[FeatureId.grades]!.status,
      FeatureLoadStatus.failure,
    );
  });
  test('成绩切换已缓存学期与视图不重读，同查询刷新仍读取学校结果', () async {
    final backend = FixtureGradesBackend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.loadAllGrades();
    const query = FeatureQuery(term: 'b', view: FeatureQueryView.gradesMissing);
    await controller.refreshFeatureQuery(FeatureId.grades, query);
    expect(backend.gradeCalls, ['a', 'b']);
    final result = controller.snapshots[FeatureId.grades]!;
    expect(result.details, hasLength(1));
    expect(result.details.single.title, '合成待出成绩');
    expect((result.overview! as GradesTermOverview).grades, hasLength(2));
    await controller.refreshFeatureQuery(FeatureId.grades, query);
    expect(backend.gradeCalls, ['a', 'b', 'b']);
  });
  test('成绩聚合复用已完成当前学期完整集合并保留各学期实际路线', () async {
    final backend = FixtureGradesBackend()
      ..defaultGrades = fixtureGradeTerm('a');
    backend.read = (term) async => fixtureGradeTerm(term, empty: term == 'b');
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.refreshHome(only: [FeatureId.grades]);
    final result = await controller.loadAllGrades();
    expect(result.isComplete, isTrue);
    expect(result.statistics.courseCount, 2);
    expect(backend.gradeCalls, ['b']);
    expect(result.terms.map((t) => t.resolvedRoute), [
      ConnectionMode.direct,
      ConnectionMode.webvpn,
    ]);
    expect(() => result.terms.clear(), throwsUnsupportedError);
    expect(
      () => result.terms.first.overview!.grades.clear(),
      throwsUnsupportedError,
    );
  });
  test('成绩某学期认证失效时不把其余缓存作为成功统计返回', () async {
    final backend = FixtureGradesBackend()
      ..read = (term) async => term == 'b'
          ? FeatureResult.failure(
              UbaaErrorMapper.fromCode(UbaaErrorCode.authenticationRequired),
            )
          : fixtureGradeTerm(term);
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    final result = await controller.loadAllGrades();
    expect(result.error?.code, UbaaErrorCode.authenticationRequired);
    expect(result.terms, isEmpty);
    expect(result.isComplete, isFalse);
    backend.read = (term) async => fixtureGradeTerm(term);
    expect((await controller.loadAllGrades()).isComplete, isTrue);
    expect(backend.gradeCalls, ['a', 'b', 'a', 'b']);
  });
  test('成绩聚合并行读取唯一学期，合并在途且不覆盖当前查询', () async {
    final gate = Completer<FeatureResult>();
    final backend = FixtureGradesBackend()..read = (_) => gate.future;
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.refreshHome(only: [FeatureId.grades]);
    final before = controller.snapshots[FeatureId.grades];
    final first = controller.loadAllGrades();
    final second = controller.loadAllGrades();
    await Future<void>.delayed(Duration.zero);
    expect(backend.gradeCalls, ['a', 'b']);
    gate.complete(fixtureGradeTerm('a'));
    final result = await first;
    expect(await second, same(result));
    expect(result.terms, hasLength(2));
    expect(result.loadedTerms, 1); // b回了a，不能伪称完整。
    expect(result.isComplete, isFalse);
    expect(result.statistics.courseCount, 2);
    expect(controller.snapshots[FeatureId.grades], same(before));
    await controller.loadGradeTerm('a');
    expect(backend.gradeCalls, ['a', 'b']);
  });

  test('成绩聚合明确局部失败、真实空学期，并可重试失败项', () async {
    var failed = true;
    final backend = FixtureGradesBackend()
      ..read = (term) async => term == 'b' && failed
          ? FeatureResult.failure(
              UbaaErrorMapper.fromCode(UbaaErrorCode.networkError),
            )
          : fixtureGradeTerm(term, empty: term == 'b');
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    final first = await controller.loadAllGrades();
    expect(first.loadedTerms, 1);
    expect(first.isComplete, isFalse);
    failed = false;
    final second = await controller.loadAllGrades();
    expect(second.loadedTerms, 2);
    expect(second.isComplete, isTrue);
    expect(second.statistics.courseCount, 2);
    expect(backend.gradeCalls, ['a', 'b', 'b']);
    await controller.loadAllGrades(forceRefresh: true);
    expect(backend.gradeCalls, ['a', 'b', 'b', 'a', 'b']);
  });

  test('成绩账号路线代次改变后旧结果失效且不能清掉新代在途', () async {
    final old = Completer<FeatureResult>(), fresh = Completer<FeatureResult>();
    final backend = FixtureGradesBackend()..read = (_) => old.future;
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    final a = controller.loadGradeTerm('a');
    await controller.setRoutePolicy(RoutePolicy.webvpn);
    backend.read = (_) => fresh.future;
    final b = controller.loadGradeTerm('a');
    old.complete(fixtureGradeTerm('a'));
    expect((await a).error?.code, UbaaErrorCode.operationConflict);
    final c = controller.loadGradeTerm('a');
    fresh.complete(fixtureGradeTerm('a'));
    expect(await b, same(await c));
    expect(backend.gradeCalls, ['a', 'a']);
    await controller.logout();
    expect(
      (await controller.loadGradeTerm('a')).error?.code,
      UbaaErrorCode.authenticationRequired,
    );
    expect(backend.gradeCalls, ['a', 'a']);
  });
}

void main() {
  _registerGradesTests();
}

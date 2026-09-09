part of '../app_controller_test.dart';

void _registerGradesTests() {
  test('成绩提醒只查唯一当前学期，未选或多个当前不猜首项', () async {
    for (final count in [0, 2, 1]) {
      final backend = _GradesBackend()
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
    final backend = _GradesBackend();
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
    final backend = _GradesBackend();
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
    final backend = _GradesBackend()..defaultGrades = _gradeTerm('a');
    backend.read = (term) async => _gradeTerm(term, empty: term == 'b');
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
    final backend = _GradesBackend()
      ..read = (term) async => term == 'b'
          ? FeatureResult.failure(
              UbaaErrorMapper.fromCode(UbaaErrorCode.authenticationRequired),
            )
          : _gradeTerm(term);
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    final result = await controller.loadAllGrades();
    expect(result.error?.code, UbaaErrorCode.authenticationRequired);
    expect(result.terms, isEmpty);
    expect(result.isComplete, isFalse);
    backend.read = (term) async => _gradeTerm(term);
    expect((await controller.loadAllGrades()).isComplete, isTrue);
    expect(backend.gradeCalls, ['a', 'b', 'a', 'b']);
  });
  test('成绩聚合并行读取唯一学期，合并在途且不覆盖当前查询', () async {
    final gate = Completer<FeatureResult>();
    final backend = _GradesBackend()..read = (_) => gate.future;
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.refreshHome(only: [FeatureId.grades]);
    final before = controller.snapshots[FeatureId.grades];
    final first = controller.loadAllGrades();
    final second = controller.loadAllGrades();
    await Future<void>.delayed(Duration.zero);
    expect(backend.gradeCalls, ['a', 'b']);
    gate.complete(_gradeTerm('a'));
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
    final backend = _GradesBackend()
      ..read = (term) async => term == 'b' && failed
          ? FeatureResult.failure(
              UbaaErrorMapper.fromCode(UbaaErrorCode.networkError),
            )
          : _gradeTerm(term, empty: term == 'b');
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
    final backend = _GradesBackend()..read = (_) => old.future;
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    final a = controller.loadGradeTerm('a');
    await controller.setRoutePolicy(RoutePolicy.webvpn);
    backend.read = (_) => fresh.future;
    final b = controller.loadGradeTerm('a');
    old.complete(_gradeTerm('a'));
    expect((await a).error?.code, UbaaErrorCode.operationConflict);
    final c = controller.loadGradeTerm('a');
    fresh.complete(_gradeTerm('a'));
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

FeatureResult _gradeTerm(String term, {bool empty = false}) {
  final overview = GradesTermOverview(
    requestTerm: term,
    termCode: term,
    grades: empty
        ? const []
        : const [
            GradePresentation(courseName: '合成课程', score: '80', credit: 2),
            GradePresentation(courseName: '合成待出成绩', credit: 1),
          ],
  );
  return empty
      ? FeatureResult.empty(
          overview: overview,
          resolvedRoute: ConnectionMode.webvpn,
        )
      : FeatureResult.success(
          overview: overview,
          resolvedRoute: ConnectionMode.direct,
        );
}

class _GradesBackend extends _QueryBackend {
  _GradesBackend() : super(onQuery: (_, _) => const FeatureResult.empty());
  final gradeCalls = <String>[];
  FeatureResult? termResult;
  FeatureResult? defaultGrades;
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      feature == FeatureId.grades && defaultGrades != null
      ? defaultGrades!
      : await super.loadFeature(feature);
  Future<FeatureResult> Function(String) read = (term) async =>
      _gradeTerm(term);
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'fixture-student');
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (query.view == FeatureQueryView.scheduleTerms) {
      if (termResult != null) return termResult!;
      return const FeatureResult.success(
        details: [
          FeatureDetail(
            title: '合成甲学期',
            presentation: TermPresentation(code: 'a', selected: true, index: 1),
          ),
          FeatureDetail(
            title: '合成乙学期',
            presentation: TermPresentation(
              code: 'b',
              selected: false,
              index: 2,
            ),
          ),
          FeatureDetail(
            title: '重复学期',
            presentation: TermPresentation(
              code: 'b',
              selected: false,
              index: 3,
            ),
          ),
        ],
      );
    }
    expect(feature, FeatureId.grades);
    gradeCalls.add(query.term!);
    return read(query.term!);
  }
}

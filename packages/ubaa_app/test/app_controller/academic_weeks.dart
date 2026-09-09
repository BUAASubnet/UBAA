part of '../app_controller_test.dart';

void _registerAcademicWeeksTests() {
  test('周选项按学期合并并发，缓存结果且不覆盖课表snapshot', () async {
    final gates = <String, Completer<FeatureResult>>{};
    final backend = _AcademicWeeksBackend(
      (term) => (gates[term] ??= Completer<FeatureResult>()).future,
    );
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.refreshHome(only: [FeatureId.schedule]);
    final before = controller.snapshots[FeatureId.schedule];
    final first = controller.loadAcademicWeeks('A');
    final second = controller.loadAcademicWeeks('A');
    final other = controller.loadAcademicWeeks('B');
    expect(backend.queries, ['A', 'B']);
    gates['A']!.complete(_weekOptions('A'));
    gates['B']!.complete(_weekOptions('B'));
    final results = await Future.wait([first, second, other]);
    expect(results[0], same(results[1]));
    expect(
      (results[2].details.single.presentation! as WeekPresentation).requestTerm,
      'B',
    );
    expect((await controller.loadAcademicWeeks('A')).error, isNull);
    expect(backend.queries, ['A', 'B']);
    expect(controller.snapshots[FeatureId.schedule], same(before));
  });
  test('周选项force失败和同步抛错不缓存，保留重试能力', () async {
    var count = 0;
    final backend = _AcademicWeeksBackend((term) {
      if (++count == 2)
        throw const BackendException(UbaaErrorCode.networkError);
      return Future.value(_weekOptions(term));
    });
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect((await controller.loadAcademicWeeks('A')).error, isNull);
    expect(
      (await controller.loadAcademicWeeks('A', forceRefresh: true)).error?.code,
      UbaaErrorCode.networkError,
    );
    expect((await controller.loadAcademicWeeks('A')).error, isNull);
    expect(count, 3);
  });
  for (final route in [false, true]) {
    test('周选项${route ? '路线' : '首页epoch'}失效后旧完成不能清理新代在途', () async {
      final old = Completer<FeatureResult>(),
          fresh = Completer<FeatureResult>();
      var count = 0;
      final backend = _AcademicWeeksBackend(
        (term) => ++count == 1 ? old.future : fresh.future,
      );
      final controller = AppController(backend: backend);
      addTearDown(controller.dispose);
      await controller.initialize();
      final first = controller.loadAcademicWeeks('A');
      if (route) {
        await controller.setRoutePolicy(RoutePolicy.direct);
      } else {
        await controller.refreshHome(only: [FeatureId.grades]);
      }
      final second = controller.loadAcademicWeeks('A');
      old.complete(_weekOptions('A'));
      expect((await first).error?.code, UbaaErrorCode.operationConflict);
      final third = controller.loadAcademicWeeks('A');
      expect(count, 2);
      fresh.complete(_weekOptions('A'));
      final results = await Future.wait([second, third]);
      expect(results.first, same(results.last));
      expect(results.first.error, isNull);
    });
  }
  test('周选项注销失效，空学期不读backend，缓存冻结外部列表', () async {
    final details = _weekOptions('A').details.toList();
    final pending = Completer<FeatureResult>();
    var count = 0;
    final backend = _AcademicWeeksBackend(
      (term) => ++count == 1
          ? Future.value(FeatureResult.success(details: details))
          : pending.future,
    );
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(
      (await controller.loadAcademicWeeks('')).error?.code,
      UbaaErrorCode.invalidInput,
    );
    final result = await controller.loadAcademicWeeks('A');
    details.clear();
    expect(result.details, hasLength(1));
    expect(() => result.details.clear(), throwsUnsupportedError);
    final late = controller.loadAcademicWeeks('B');
    await controller.logout();
    pending.complete(_weekOptions('B'));
    expect((await late).error?.code, UbaaErrorCode.operationConflict);
    expect(
      (await controller.loadAcademicWeeks('A')).error?.code,
      UbaaErrorCode.authenticationRequired,
    );
    expect(count, 2);
  });
}

FeatureResult _weekOptions(String term) => FeatureResult.success(
  details: [
    FeatureDetail(
      title: '合成第4周',
      presentation: WeekPresentation(
        requestTerm: term,
        responseTerm: term,
        number: 4,
        current: true,
        startDate: '2026-09-07',
        endDate: '2026-09-13',
      ),
    ),
  ],
  resolvedRoute: ConnectionMode.webvpn,
);

class _AcademicWeeksBackend extends _QueryBackend {
  _AcademicWeeksBackend(this.load)
    : super(onQuery: (_, _) => const FeatureResult.empty());
  final Future<FeatureResult> Function(String) load;
  final queries = <String>[];
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'fixture-student');
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) {
    expect(feature, FeatureId.schedule);
    expect(query.view, FeatureQueryView.scheduleWeeks);
    queries.add(query.term!);
    return load(query.term!);
  }
}

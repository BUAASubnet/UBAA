part of '../app_controller_test.dart';

void _registerAcademicTermsTests() {
  test('学期选项合并并发并缓存成功且不改课表snapshot', () async {
    final pending = Completer<FeatureResult>();
    final backend = _AcademicTermsBackend(() => pending.future);
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    // initialize 会异步启动首页加载；等待课表基线终态后再观察独立选项请求。
    await controller.refreshHome(only: [FeatureId.schedule]);
    final before = controller.snapshots[FeatureId.schedule];
    final first = controller.loadAcademicTerms();
    final second = controller.loadAcademicTerms();
    expect(backend.queries, hasLength(1));
    pending.complete(_termOptions());
    final results = await Future.wait([first, second]);
    expect(results.every((result) => result.error == null), isTrue);
    expect(results.first.details.single.presentation, isA<TermPresentation>());
    await controller.loadAcademicTerms();
    expect(backend.queries, hasLength(1));
    expect(backend.queries.single.view, FeatureQueryView.scheduleTerms);
    expect(controller.snapshots[FeatureId.schedule], same(before));
  });

  test('旧代学期完成不得清理新代在途句柄第三次调用仍合并', () async {
    final oldRequest = Completer<FeatureResult>();
    final newRequest = Completer<FeatureResult>();
    var calls = 0;
    final backend = _AcademicTermsBackend(() {
      calls++;
      if (calls == 1) return oldRequest.future;
      if (calls == 2) return newRequest.future;
      fail('第三次调用必须合并新代在途请求，不能新增网络调用');
    });
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    final first = controller.loadAcademicTerms();
    expect(calls, 1);
    await controller.refreshHome(only: [FeatureId.grades]);
    final second = controller.loadAcademicTerms();
    expect(calls, 2);
    oldRequest.complete(_termOptions());
    expect((await first).error?.code, UbaaErrorCode.operationConflict);
    expect(newRequest.isCompleted, isFalse);
    final third = controller.loadAcademicTerms();
    expect(calls, 2);
    newRequest.complete(_termOptions());
    final results = await Future.wait([second, third]);
    expect(results.every((result) => result.error == null), isTrue);
    expect(results.first, same(results.last));
    expect(backend.queries, hasLength(2));
    expect((await controller.loadAcademicTerms()).error, isNull);
    expect(calls, 2);
  });

  test('backend重建使旧学期请求失败而新backend独立加载', () async {
    final delayed = Completer<FeatureResult>();
    final old = _AcademicTermsBackend(() => delayed.future);
    final replacement = _AcademicTermsBackend(() async => _termOptions());
    final controller = AppController(
      backend: old,
      backendFactory: () => replacement,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final first = controller.loadAcademicTerms();
    expect(await controller.rebuildBackend(), isTrue);
    final fresh = await controller.loadAcademicTerms();
    delayed.complete(_termOptions());
    expect((await first).error?.code, UbaaErrorCode.operationConflict);
    expect(fresh.error, isNull);
    expect(old.queries, hasLength(1));
    expect(replacement.queries, hasLength(1));
    await controller.loadAcademicTerms();
    expect(replacement.queries, hasLength(1));
  });

  test('backend显式failure不缓存并允许随后安全重读', () async {
    var requests = 0;
    final controller = AppController(
      backend: _AcademicTermsBackend(() async {
        if (++requests == 1)
          return FeatureResult.failure(
            UbaaErrorMapper.fromCode(UbaaErrorCode.networkError),
          );
        return _termOptions();
      }),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(
      (await controller.loadAcademicTerms()).error?.code,
      UbaaErrorCode.networkError,
    );
    expect((await controller.loadAcademicTerms()).error, isNull);
    expect(requests, 2);
  });

  test('同步抛错的学期backend不会留下已失败的在途句柄', () async {
    var requests = 0;
    final controller = AppController(
      backend: _AcademicTermsBackend(() {
        if (++requests == 1)
          throw const BackendException(UbaaErrorCode.networkError);
        return Future.value(_termOptions());
      }),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(
      (await controller.loadAcademicTerms()).error?.code,
      UbaaErrorCode.networkError,
    );
    expect((await controller.loadAcademicTerms()).error, isNull);
    expect(requests, 2);
  });

  test('学期force重读错误不缓存且随后重试成功', () async {
    var requests = 0;
    final controller = AppController(
      backend: _AcademicTermsBackend(() async {
        requests++;
        if (requests == 2)
          throw const BackendException(UbaaErrorCode.networkError);
        return _termOptions();
      }),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect((await controller.loadAcademicTerms()).error, isNull);
    expect(
      (await controller.loadAcademicTerms(forceRefresh: true)).error?.code,
      UbaaErrorCode.networkError,
    );
    expect((await controller.loadAcademicTerms()).error, isNull);
    expect(requests, 3);
  });

  test('学期成功选项冻结外部列表与导航keys防止调用者污染缓存', () async {
    final keys = <JudgeAssignmentQueryKey>[
      const JudgeAssignmentQueryKey(courseId: 'c', assignmentId: 'a'),
    ];
    final details = <FeatureDetail>[
      FeatureDetail(
        title: '合成学期',
        presentation: const TermPresentation(
          code: 'term',
          selected: true,
          index: 1,
        ),
        readNavigation: FeatureReadNavigation(
          feature: FeatureId.schedule,
          query: FeatureQuery(
            view: FeatureQueryView.scheduleWeeks,
            term: 'term',
            judgeKeys: keys,
          ),
        ),
      ),
    ];
    final controller = AppController(
      backend: _AcademicTermsBackend(
        () async => FeatureResult.success(details: details),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final first = await controller.loadAcademicTerms();
    expect(first.error, isNull);
    keys.clear();
    details.clear();
    final cached = await controller.loadAcademicTerms();
    expect(cached.details, hasLength(1));
    expect(cached.details.single.readNavigation!.query.judgeKeys, hasLength(1));
    expect(() => cached.details.clear(), throwsUnsupportedError);
    expect(
      () => cached.details.single.readNavigation!.query.judgeKeys.clear(),
      throwsUnsupportedError,
    );
  });

  test('首页epoch与路线生命周期使迟到学期结果失败且不能回填新缓存', () async {
    for (final changeRoute in [false, true]) {
      final delayed = Completer<FeatureResult>();
      var requests = 0;
      final controller = AppController(
        backend: _AcademicTermsBackend(() {
          requests++;
          return requests == 1 ? delayed.future : Future.value(_termOptions());
        }),
      );
      await controller.initialize();
      final old = controller.loadAcademicTerms();
      if (changeRoute) {
        await controller.setRoutePolicy(RoutePolicy.direct);
      } else {
        await controller.refreshHome(only: [FeatureId.grades]);
      }
      delayed.complete(_termOptions());
      expect((await old).error?.code, UbaaErrorCode.operationConflict);
      expect((await controller.loadAcademicTerms()).error, isNull);
      expect(requests, 2);
      controller.dispose();
    }
  });

  test('注销开始使学期在途失效且未认证请求不读backend', () async {
    final delayed = Completer<FeatureResult>();
    final backend = _AcademicTermsBackend(() => delayed.future);
    final controller = AppController(backend: backend);
    await controller.initialize();
    final request = controller.loadAcademicTerms();
    await controller.logout();
    delayed.complete(_termOptions());
    expect((await request).error?.code, UbaaErrorCode.operationConflict);
    expect(
      (await controller.loadAcademicTerms()).error?.code,
      UbaaErrorCode.authenticationRequired,
    );
    expect(backend.queries, hasLength(1));
    controller.dispose();
  });
}

FeatureResult _termOptions() => const FeatureResult.success(
  details: [
    FeatureDetail(
      title: '合成学期',
      presentation: TermPresentation(
        code: '2026-2027-1',
        selected: true,
        index: 1,
      ),
    ),
  ],
  resolvedRoute: ConnectionMode.webvpn,
);

class _AcademicTermsBackend extends _QueryBackend {
  _AcademicTermsBackend(this.load)
    : super(onQuery: (_, _) => const FeatureResult.empty());
  final Future<FeatureResult> Function() load;
  final queries = <FeatureQuery>[];
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
    queries.add(query);
    return load();
  }
}

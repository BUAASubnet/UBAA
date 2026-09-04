part of '../app_controller_test.dart';

void _registerYgdkWriteTests() {
  test('阳光打卡写意图只接受 allowed canonical action 和完整内存输入', () async {
    final backend = _YgdkWriteBackend();
    final controller = AppController(backend: backend);
    const action = YgdkSubmitAction(
      classifyId: 31,
      itemId: 7,
      eligibility: ActionEligibility.allowed,
    );
    final intent = await controller.prepareYgdkWrite(
      const YgdkSubmitInput(
        action: action,
        startTime: '2026-09-01 09:00',
        endTime: '2026-09-01 10:00',
        place: '  校园  ',
        shareToSquare: false,
        photo: YgdkPhotoInput(
          bytes: <int>[1, 2, 3],
          fileName: 'safe.jpg',
          mimeType: 'image/jpeg',
        ),
      ),
    );
    expect(intent.operation, WriteOperation.ygdkSubmit);
    expect(backend.input?.action, same(action));
    expect(backend.input?.action.classifyId, 31);
    expect(backend.input?.action.itemId, 7);
    expect(backend.input?.startTime, '2026-09-01 09:00');
    expect(backend.input?.endTime, '2026-09-01 10:00');
    expect(backend.input?.place, '校园');
    expect(backend.input?.shareToSquare, isFalse);
    expect(backend.input?.photo.fileName, 'safe.jpg');
    expect(backend.commitCalls, 0);

    for (final invalid in <YgdkSubmitInput>[
      _ygdkInput(
        action: const YgdkSubmitAction(
          classifyId: 31,
          itemId: 7,
          eligibility: ActionEligibility.unknown,
        ),
      ),
      _ygdkInput(
        action: const YgdkSubmitAction(
          classifyId: 0,
          itemId: 7,
          eligibility: ActionEligibility.allowed,
        ),
      ),
      _ygdkInput(startTime: ' 2026-09-01 09:00'),
      _ygdkInput(endTime: '2026-09-01 10:00 '),
      _ygdkInput(startTime: '2026-09-01T09:00'),
      _ygdkInput(startTime: '2026-09-01 09:00:00'),
      _ygdkInput(startTime: '2026-02-30 09:00'),
      _ygdkInput(endTime: '2026-09-02 10:00'),
      _ygdkInput(endTime: '2026-09-01 09:00'),
      _ygdkInput(endTime: '2026-09-01 08:59'),
      _ygdkInput(photoBytes: const <int>[]),
      _ygdkInput(photoBytes: Uint8List(10 * 1024 * 1024 + 1)),
      _ygdkInput(photoBytes: const <int>[-1]),
      _ygdkInput(photoBytes: const <int>[256]),
      _ygdkInput(fileName: ' safe.jpg'),
      _ygdkInput(fileName: 'safe.jpg '),
      _ygdkInput(fileName: '.'),
      _ygdkInput(fileName: '..'),
      _ygdkInput(fileName: 'folder/safe.jpg'),
      _ygdkInput(fileName: r'folder\safe.jpg'),
      _ygdkInput(fileName: 'bad"name.jpg'),
      _ygdkInput(fileName: 'bad\nname.jpg'),
      _ygdkInput(fileName: List<String>.filled(129, 'a').join()),
      _ygdkInput(mimeType: 'Image/jpeg'),
      _ygdkInput(mimeType: 'image/jpeg '),
      _ygdkInput(mimeType: 'image/jpeg; charset=utf-8'),
      _ygdkInput(mimeType: 'image/'),
      _ygdkInput(mimeType: 'image/a/b'),
      _ygdkInput(mimeType: 'image/图片'),
      _ygdkInput(mimeType: 'image/jpeg\n'),
    ]) {
      await expectLater(
        controller.prepareYgdkWrite(invalid),
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            'code',
            UbaaErrorCode.invalidInput,
          ),
        ),
      );
    }
    expect(backend.input?.action, same(action));
    controller.dispose();
  });

  test('阳光打卡写后在原路线独立刷新概览和首页记录', () async {
    final backend = _YgdkReadbackBackend(
      overview: const FeatureResult.success(
        summary: '学期进度 1/10',
        resolvedRoute: ConnectionMode.direct,
      ),
      records: const FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: <FeatureDetail>[
          FeatureDetail(
            title: '只读记录页',
            fields: <FeatureField>[FeatureField(label: '记录编号', value: '999')],
          ),
        ],
      ),
    );
    final controller = AppController(backend: backend);

    await controller.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );
    expect(backend.overviewRoutes, const <ConnectionMode>[
      ConnectionMode.direct,
    ]);
    expect(backend.recordsRoutes, const <ConnectionMode>[
      ConnectionMode.direct,
    ]);
    expect(backend.recordPages, const <(int, int)>[(1, 20)]);
    expect(controller.ygdkReadbackState.overview.summary, '学期进度 1/10');
    expect(controller.ygdkReadbackState.records.details.single.title, '只读记录页');
    expect(controller.snapshots[FeatureId.ygdk]!.summary, '学期进度 1/10');
    expect(controller.snapshots[FeatureId.ygdk]!.details, isEmpty);
    controller.dispose();
  });

  test('阳光打卡回读忽略路线冲突的概览但仍独立刷新记录', () async {
    final backend = _YgdkReadbackBackend(
      overview: const FeatureResult.success(
        summary: '错路线概览',
        resolvedRoute: ConnectionMode.webvpn,
      ),
      records: const FeatureResult.success(
        summary: '原路线记录',
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    final controller = AppController(backend: backend);

    await controller.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );

    expect(backend.overviewRoutes, const <ConnectionMode>[
      ConnectionMode.direct,
    ]);
    expect(backend.recordsRoutes, const <ConnectionMode>[
      ConnectionMode.direct,
    ]);
    expect(
      controller.ygdkReadbackState.overview.error?.code,
      UbaaErrorCode.operationConflict,
    );
    expect(controller.ygdkReadbackState.records.summary, '原路线记录');
    expect(
      controller.snapshots[FeatureId.ygdk]!.status,
      FeatureLoadStatus.idle,
    );
    controller.dispose();
  });

  test('阳光打卡概览回读失败不阻断原路线记录刷新', () async {
    final backend = _YgdkReadbackBackend(
      overview: const FeatureResult.success(
        summary: '不应写入的概览',
        resolvedRoute: ConnectionMode.direct,
      ),
      records: const FeatureResult.success(
        summary: '原路线记录',
        resolvedRoute: ConnectionMode.direct,
      ),
      overviewFailure: StateError('概览暂不可用'),
    );
    final controller = AppController(backend: backend);

    await controller.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );

    expect(backend.overviewRoutes, const <ConnectionMode>[
      ConnectionMode.direct,
    ]);
    expect(backend.recordsRoutes, const <ConnectionMode>[
      ConnectionMode.direct,
    ]);
    expect(
      controller.ygdkReadbackState.overview.error?.code,
      UbaaErrorCode.internalError,
    );
    expect(
      controller.ygdkReadbackState.overview.error?.technicalDetail,
      isNull,
    );
    expect(controller.ygdkReadbackState.records.summary, '原路线记录');
    expect(
      controller.snapshots[FeatureId.ygdk]!.status,
      FeatureLoadStatus.idle,
    );
    controller.dispose();
  });

  test('阳光打卡记录回读失败不撤销已刷新的概览', () async {
    final backend = _YgdkReadbackBackend(
      overview: const FeatureResult.success(
        summary: '原路线概览',
        resolvedRoute: ConnectionMode.webvpn,
      ),
      records: const FeatureResult.success(
        summary: '不应写入的记录',
        resolvedRoute: ConnectionMode.webvpn,
      ),
      recordsFailure: StateError('记录暂不可用'),
    );
    final controller = AppController(backend: backend);

    await controller.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.webvpn,
    );

    expect(backend.overviewRoutes, const <ConnectionMode>[
      ConnectionMode.webvpn,
    ]);
    expect(backend.recordsRoutes, const <ConnectionMode>[
      ConnectionMode.webvpn,
    ]);
    expect(controller.ygdkReadbackState.overview.summary, '原路线概览');
    expect(
      controller.ygdkReadbackState.records.error?.code,
      UbaaErrorCode.internalError,
    );
    expect(controller.snapshots[FeatureId.ygdk]!.summary, '原路线概览');
    controller.dispose();
  });

  test('阳光打卡 empty 与安全 failure 分别落入独立槽位', () async {
    final backend = _YgdkReadbackBackend(
      overview: const FeatureResult.empty(resolvedRoute: ConnectionMode.direct),
      records: const FeatureResult.failure(
        UiError(
          code: UbaaErrorCode.networkError,
          title: '不应透传',
          message: '不应透传',
          technicalDetail: 'token=secret',
        ),
      ),
    );
    final controller = AppController(backend: backend);

    await controller.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );

    expect(
      controller.ygdkReadbackState.overview.status,
      FeatureLoadStatus.empty,
    );
    expect(
      controller.ygdkReadbackState.records.status,
      FeatureLoadStatus.failure,
    );
    expect(
      controller.ygdkReadbackState.records.error?.code,
      UbaaErrorCode.networkError,
    );
    expect(controller.ygdkReadbackState.records.error?.technicalDetail, isNull);
    expect(
      controller.snapshots[FeatureId.ygdk]!.status,
      FeatureLoadStatus.empty,
    );
    controller.dispose();
  });

  test('阳光打卡独立回读槽在注销后清空', () async {
    final backend = _successfulYgdkReadbackBackend();
    final controller = AppController(backend: backend);
    await controller.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );
    expect(controller.ygdkReadbackState.overview.updatedAt, isNotNull);
    expect(controller.ygdkReadbackState.records.updatedAt, isNotNull);

    await controller.logout();

    _expectEmptyYgdkReadbackState(controller.ygdkReadbackState);
    expect(
      controller.snapshots[FeatureId.ygdk]!.status,
      FeatureLoadStatus.idle,
    );
    controller.dispose();
  });

  test('阳光打卡独立回读槽在 backend 重建后清空', () async {
    final first = _successfulYgdkReadbackBackend();
    final replacement = _successfulYgdkReadbackBackend();
    final controller = AppController(
      backend: first,
      backendFactory: () => replacement,
    );
    await controller.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );

    expect(await controller.rebuildBackend(), isTrue);

    _expectEmptyYgdkReadbackState(controller.ygdkReadbackState);
    controller.dispose();
  });

  test('backend 重建一开始就使进行中的阳光打卡回读过时', () async {
    final backend = _DelayedDisposableYgdkReadbackBackend();
    final controller = AppController(
      backend: backend,
      backendFactory: _successfulYgdkReadbackBackend,
    );
    final pendingReadback = controller.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );
    await backend.overviewStarted.future;

    final rebuilding = controller.rebuildBackend();
    await backend.disposeStarted.future;
    backend.overview.complete(
      const FeatureResult.success(
        summary: '不应回写的旧概览',
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    await Future.any<void>(<Future<void>>[
      pendingReadback,
      backend.recordsStarted.future,
    ]);
    if (backend.recordsStarted.isCompleted) {
      backend.records.complete(
        const FeatureResult.success(
          summary: '不应回写的旧记录',
          resolvedRoute: ConnectionMode.direct,
        ),
      );
    }
    await pendingReadback;

    try {
      expect(backend.recordsStarted.isCompleted, isFalse);
      _expectEmptyYgdkReadbackState(controller.ygdkReadbackState);
    } finally {
      backend.releaseDispose.complete();
      await rebuilding;
      controller.dispose();
    }
  });

  test('阳光打卡独立回读槽在 controller 销毁后清空', () async {
    final controller = AppController(backend: _successfulYgdkReadbackBackend());
    await controller.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );

    controller.dispose();

    _expectEmptyYgdkReadbackState(controller.ygdkReadbackState);
    expect(
      controller.snapshots[FeatureId.ygdk]!.status,
      FeatureLoadStatus.idle,
    );
  });

  test('延迟全量刷新期间的阳光打卡回读不会使其他功能永久 loading', () async {
    final backend = _DelayedFullRefreshYgdkBackend();
    final controller = AppController(backend: backend);
    final refreshing = controller.refreshHome();
    await backend.scheduleStarted.future;

    await controller.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );
    backend.schedule.complete(
      const FeatureResult.success(
        summary: '课程表已刷新',
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    await refreshing;

    expect(
      controller.snapshots[FeatureId.schedule]!.status,
      FeatureLoadStatus.success,
    );
    expect(controller.snapshots[FeatureId.schedule]!.summary, '课程表已刷新');
    controller.dispose();
  });

  test('后启动的阳光打卡回读不被早启动的延迟摘要覆盖', () async {
    final backend = _DelayedYgdkFeatureBackend();
    final controller = AppController(backend: backend);
    final refreshing = controller.refreshHome(
      only: const <FeatureId>[FeatureId.ygdk],
    );
    await backend.featureStarted.future;

    await controller.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );
    expect(controller.snapshots[FeatureId.ygdk]!.summary, '写后概览');
    backend.feature.complete(
      const FeatureResult.success(
        summary: '过时摘要',
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    await refreshing;

    expect(controller.snapshots[FeatureId.ygdk]!.summary, '写后概览');
    controller.dispose();
  });

  test('延迟摘要被失败写后回读取代时不会永久 loading', () async {
    final backend = _DelayedYgdkFeatureWithFailedOverviewBackend();
    final controller = AppController(backend: backend);
    final refreshing = controller.refreshHome(
      only: const <FeatureId>[FeatureId.ygdk],
    );
    await backend.featureStarted.future;
    expect(
      controller.snapshots[FeatureId.ygdk]!.status,
      FeatureLoadStatus.loading,
    );

    await controller.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );

    expect(
      controller.snapshots[FeatureId.ygdk]!.status,
      FeatureLoadStatus.failure,
    );
    expect(
      controller.snapshots[FeatureId.ygdk]!.error?.code,
      UbaaErrorCode.internalError,
    );
    expect(controller.ygdkReadbackState.records.summary, '写后记录');

    backend.feature.complete(
      const FeatureResult.success(
        summary: '过时摘要',
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    await refreshing;

    expect(
      controller.snapshots[FeatureId.ygdk]!.status,
      FeatureLoadStatus.failure,
    );
    controller.dispose();
  });

  test('无关功能 retry 不取消进行中的阳光打卡回读', () async {
    final backend = _DelayedYgdkReadbackBackend();
    final controller = AppController(backend: backend);
    final pending = controller.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );
    await backend.overviewStarted.future;

    await controller.retryFeature(FeatureId.schedule);
    backend.overview.complete(
      const FeatureResult.success(
        summary: '并发概览',
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    await backend.recordsStarted.future;
    backend.records.complete(
      const FeatureResult.success(
        summary: '并发记录',
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    await pending;

    expect(controller.ygdkReadbackState.overview.summary, '并发概览');
    expect(controller.ygdkReadbackState.records.summary, '并发记录');
    controller.dispose();
  });

  test('注销使进行中的阳光打卡回读过时且不回写', () async {
    final backend = _DelayedYgdkReadbackBackend();
    final controller = AppController(backend: backend);
    final pending = controller.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );
    await backend.overviewStarted.future;

    await controller.logout();
    backend.records.complete(
      const FeatureResult.success(
        summary: '不应读取的记录',
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    backend.overview.complete(
      const FeatureResult.success(
        summary: '不应回写的概览',
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    await pending;

    expect(backend.recordsStarted.isCompleted, isFalse);
    _expectEmptyYgdkReadbackState(controller.ygdkReadbackState);
    controller.dispose();
  });

  test('延迟注销一开始就使进行中的阳光打卡回读过时', () async {
    final backend = _DelayedLogoutYgdkReadbackBackend();
    final controller = AppController(backend: backend);
    final pending = controller.refreshYgdkAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );
    await backend.overviewStarted.future;

    final loggingOut = controller.logout();
    await backend.logoutStarted.future;
    backend.records.complete(
      const FeatureResult.success(
        summary: '不应读取的记录',
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    backend.overview.complete(
      const FeatureResult.success(
        summary: '不应回写的概览',
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    try {
      await pending;
      expect(backend.recordsStarted.isCompleted, isFalse);
      _expectEmptyYgdkReadbackState(controller.ygdkReadbackState);
    } finally {
      backend.releaseLogout.complete();
      await loggingOut;
      controller.dispose();
    }
  });
}

_YgdkReadbackBackend _successfulYgdkReadbackBackend() => _YgdkReadbackBackend(
  overview: const FeatureResult.success(
    summary: '概览',
    resolvedRoute: ConnectionMode.direct,
  ),
  records: const FeatureResult.success(
    summary: '记录',
    resolvedRoute: ConnectionMode.direct,
  ),
);

void _expectEmptyYgdkReadbackState(YgdkReadbackState state) {
  expect(state.overview.status, FeatureLoadStatus.idle);
  expect(state.records.status, FeatureLoadStatus.idle);
  expect(state.overview.updatedAt, isNull);
  expect(state.records.updatedAt, isNull);
}

final class _DelayedYgdkReadbackBackend
    implements UbaaBackend, YgdkSubmissionReadbackBackend {
  final Completer<void> overviewStarted = Completer<void>();
  final Completer<void> recordsStarted = Completer<void>();
  final Completer<FeatureResult> overview = Completer<FeatureResult>();
  final Completer<FeatureResult> records = Completer<FeatureResult>();

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'student');

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<FeatureResult> loadYgdkOverviewOnRoute({
    required ConnectionMode route,
  }) {
    overviewStarted.complete();
    return overview.future;
  }

  @override
  Future<FeatureResult> loadYgdkRecordsOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) {
    recordsStarted.complete();
    return records.future;
  }
}

YgdkSubmitInput _ygdkInput({
  YgdkSubmitAction action = const YgdkSubmitAction(
    classifyId: 31,
    itemId: 7,
    eligibility: ActionEligibility.allowed,
  ),
  String startTime = '2026-09-01 09:00',
  String endTime = '2026-09-01 10:00',
  String? place,
  bool shareToSquare = false,
  List<int>? photoBytes,
  String fileName = 'safe.jpg',
  String mimeType = 'image/jpeg',
}) => YgdkSubmitInput(
  action: action,
  startTime: startTime,
  endTime: endTime,
  place: place,
  shareToSquare: shareToSquare,
  photo: YgdkPhotoInput(
    bytes: photoBytes ?? const <int>[1],
    fileName: fileName,
    mimeType: mimeType,
  ),
);

class _YgdkReadbackBackend
    implements UbaaBackend, YgdkSubmissionReadbackBackend {
  _YgdkReadbackBackend({
    required this.overview,
    required this.records,
    this.overviewFailure,
    this.recordsFailure,
  });

  final FeatureResult overview;
  final FeatureResult records;
  final Object? overviewFailure;
  final Object? recordsFailure;
  final List<ConnectionMode> overviewRoutes = <ConnectionMode>[];
  final List<ConnectionMode> recordsRoutes = <ConnectionMode>[];
  final List<(int, int)> recordPages = <(int, int)>[];

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'student');

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<FeatureResult> loadYgdkOverviewOnRoute({
    required ConnectionMode route,
  }) async {
    overviewRoutes.add(route);
    if (overviewFailure case final failure?) throw failure;
    return overview;
  }

  @override
  Future<FeatureResult> loadYgdkRecordsOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) async {
    recordsRoutes.add(route);
    recordPages.add((page, size));
    if (recordsFailure case final failure?) throw failure;
    return records;
  }
}

final class _DelayedFullRefreshYgdkBackend extends _YgdkReadbackBackend {
  _DelayedFullRefreshYgdkBackend()
    : super(
        overview: const FeatureResult.success(
          summary: '打卡概览',
          resolvedRoute: ConnectionMode.direct,
        ),
        records: const FeatureResult.success(
          summary: '打卡记录',
          resolvedRoute: ConnectionMode.direct,
        ),
      );

  final Completer<void> scheduleStarted = Completer<void>();
  final Completer<FeatureResult> schedule = Completer<FeatureResult>();

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) {
    if (feature != FeatureId.schedule) {
      return Future<FeatureResult>.value(
        FeatureResult.success(summary: feature.title),
      );
    }
    scheduleStarted.complete();
    return schedule.future;
  }
}

final class _DelayedYgdkFeatureBackend extends _YgdkReadbackBackend {
  _DelayedYgdkFeatureBackend()
    : super(
        overview: const FeatureResult.success(
          summary: '写后概览',
          resolvedRoute: ConnectionMode.direct,
        ),
        records: const FeatureResult.success(
          summary: '写后记录',
          resolvedRoute: ConnectionMode.direct,
        ),
      );

  final Completer<void> featureStarted = Completer<void>();
  final Completer<FeatureResult> feature = Completer<FeatureResult>();

  @override
  Future<FeatureResult> loadFeature(FeatureId featureId) {
    featureStarted.complete();
    return feature.future;
  }
}

final class _DelayedYgdkFeatureWithFailedOverviewBackend
    extends _YgdkReadbackBackend {
  _DelayedYgdkFeatureWithFailedOverviewBackend()
    : super(
        overview: const FeatureResult.success(
          summary: '不应写入的概览',
          resolvedRoute: ConnectionMode.direct,
        ),
        records: const FeatureResult.success(
          summary: '写后记录',
          resolvedRoute: ConnectionMode.direct,
        ),
        overviewFailure: StateError('概览暂不可用'),
      );

  final Completer<void> featureStarted = Completer<void>();
  final Completer<FeatureResult> feature = Completer<FeatureResult>();

  @override
  Future<FeatureResult> loadFeature(FeatureId featureId) {
    featureStarted.complete();
    return feature.future;
  }
}

final class _DelayedLogoutYgdkReadbackBackend
    extends _DelayedYgdkReadbackBackend {
  final Completer<void> logoutStarted = Completer<void>();
  final Completer<void> releaseLogout = Completer<void>();

  @override
  Future<void> logout() async {
    logoutStarted.complete();
    await releaseLogout.future;
  }
}

final class _DelayedDisposableYgdkReadbackBackend
    extends _DelayedYgdkReadbackBackend
    implements BackendLifecycle {
  final Completer<void> disposeStarted = Completer<void>();
  final Completer<void> releaseDispose = Completer<void>();

  @override
  Future<void> dispose() async {
    disposeStarted.complete();
    await releaseDispose.future;
  }
}

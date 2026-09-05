part of '../app_controller_test.dart';

void _registerEvaluationTests() {
  test('评教 prepare 只传递规范化 typed targets 并保持顺序', () async {
    final backend = _EvaluationBackend();
    final controller = AppController(backend: backend);

    final intent = await controller
        .prepareEvaluationWrite(const <EvaluationSubmitTarget>[
          EvaluationSubmitTarget(
            rwid: ' task-1 ',
            wjid: ' form-1 ',
            kcdm: ' course-1 ',
            bpdm: ' teacher-1 ',
          ),
          EvaluationSubmitTarget(
            rwid: 'task-2',
            wjid: 'form-2',
            kcdm: 'course-2',
            bpdm: '   ',
          ),
        ]);

    expect(intent.operation, WriteOperation.evaluationSubmitCourses);
    expect(backend.targets.map((target) => target.selectionKey), const <String>[
      '6:task-1|6:form-1|8:course-1|9:teacher-1',
      '6:task-2|6:form-2|8:course-2|0:',
    ]);
    expect(backend.targets.last.bpdm, isNull);
    expect(backend.commitCalls, 0);
    controller.dispose();
  });

  test('评教 prepare 在空组、缺失身份或规范化重复时失败关闭', () async {
    final backend = _EvaluationBackend();
    final controller = AppController(backend: backend);
    final invalidRequests = <List<EvaluationSubmitTarget>>[
      const <EvaluationSubmitTarget>[],
      const <EvaluationSubmitTarget>[
        EvaluationSubmitTarget(rwid: ' ', wjid: 'form', kcdm: 'course'),
      ],
      const <EvaluationSubmitTarget>[
        EvaluationSubmitTarget(rwid: 'task', wjid: 'form', kcdm: 'course'),
        EvaluationSubmitTarget(
          rwid: ' task ',
          wjid: ' form ',
          kcdm: ' course ',
          bpdm: '',
        ),
      ],
    ];

    for (final request in invalidRequests) {
      await expectLater(
        controller.prepareEvaluationWrite(request),
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            'code',
            UbaaErrorCode.invalidInput,
          ),
        ),
      );
    }

    expect(backend.prepareCalls, 0);
    controller.dispose();
  });

  test('评教提交能力必须将 typed 写入与原路线回读成对暴露', () {
    final complete = AppController(backend: _EvaluationBackend());
    final writeOnly = AppController(backend: _EvaluationWriteOnlyBackend());
    final readbackOnly = AppController(
      backend: _EvaluationReadbackOnlyBackend(),
    );

    expect(complete.hasEvaluationSubmissionBackendCapabilities, isTrue);
    expect(writeOnly.hasEvaluationSubmissionBackendCapabilities, isFalse);
    expect(readbackOnly.hasEvaluationSubmissionBackendCapabilities, isFalse);

    complete.dispose();
    writeOnly.dispose();
    readbackOnly.dispose();
  });

  test('评教写后回读恰好一次使用 intent 原路线并更新单领域快照', () async {
    final backend = _EvaluationBackend(
      readbackResult: const FeatureResult.success(
        summary: '回读完成',
        details: <FeatureDetail>[FeatureDetail(title: '评教课程')],
        resolvedRoute: ConnectionMode.webvpn,
      ),
    );
    final controller = AppController(backend: backend);

    await controller.refreshEvaluationAfterWrite(
      expectedRoute: ConnectionMode.webvpn,
    );

    expect(backend.readbackRoutes, const <ConnectionMode>[
      ConnectionMode.webvpn,
    ]);
    final snapshot = controller.snapshots[FeatureId.evaluation]!;
    expect(snapshot.status, FeatureLoadStatus.success);
    expect(snapshot.summary, '回读完成');
    expect(snapshot.details.single.title, '评教课程');
    expect(snapshot.resolvedRoute, ConnectionMode.webvpn);
    controller.dispose();
  });

  test('评教回读失败或路线冲突只标记读取失败且不重试', () async {
    final cases = <_EvaluationBackend>[
      _EvaluationBackend(readbackError: UbaaErrorCode.networkError),
      _EvaluationBackend(
        readbackResult: const FeatureResult.success(
          summary: '错误路线',
          resolvedRoute: ConnectionMode.direct,
        ),
      ),
    ];

    for (final backend in cases) {
      final controller = AppController(backend: backend);
      await controller.refreshEvaluationAfterWrite(
        expectedRoute: ConnectionMode.webvpn,
      );

      expect(backend.readbackRoutes, const <ConnectionMode>[
        ConnectionMode.webvpn,
      ]);
      final snapshot = controller.snapshots[FeatureId.evaluation]!;
      expect(snapshot.status, FeatureLoadStatus.failure);
      expect(snapshot.error, isNotNull);
      controller.dispose();
    }
  });
}

abstract class _EvaluationBackendBase implements UbaaBackend {
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
}

class _EvaluationWriteOnlyBackend extends _EvaluationBackendBase
    with _DiscardingWriteBackendFake
    implements EvaluationWriteBackend {
  @override
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationSubmitTarget> targets,
  ) async => _evaluationIntent();

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async =>
      const WriteCommitResult(
        operation: WriteOperation.evaluationSubmitCourses,
        success: true,
        message: '已提交',
        outcomeUnknown: false,
      );
}

class _EvaluationReadbackOnlyBackend extends _EvaluationBackendBase
    implements EvaluationSubmissionReadbackBackend {
  @override
  Future<FeatureResult> loadEvaluationOnRoute({
    required ConnectionMode route,
  }) async => const FeatureResult.empty();
}

class _EvaluationBackend extends _EvaluationWriteOnlyBackend
    implements EvaluationSubmissionReadbackBackend {
  _EvaluationBackend({
    this.readbackResult = const FeatureResult.empty(
      resolvedRoute: ConnectionMode.direct,
    ),
    this.readbackError,
  });

  final FeatureResult readbackResult;
  final UbaaErrorCode? readbackError;
  List<EvaluationSubmitTarget> targets = const <EvaluationSubmitTarget>[];
  final List<ConnectionMode> readbackRoutes = <ConnectionMode>[];
  int prepareCalls = 0;
  int commitCalls = 0;

  @override
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationSubmitTarget> targets,
  ) async {
    prepareCalls++;
    this.targets = List<EvaluationSubmitTarget>.unmodifiable(targets);
    return _evaluationIntent();
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    return const WriteCommitResult(
      operation: WriteOperation.evaluationSubmitCourses,
      success: true,
      message: '已提交',
      outcomeUnknown: false,
    );
  }

  @override
  Future<FeatureResult> loadEvaluationOnRoute({
    required ConnectionMode route,
  }) async {
    readbackRoutes.add(route);
    if (readbackError case final code?) throw BackendException(code);
    return readbackResult;
  }
}

WriteIntent _evaluationIntent() => WriteIntent(
  intentId: 'evaluation-intent',
  operation: WriteOperation.evaluationSubmitCourses,
  targetSummary: '教学评教',
  resolvedRoute: ConnectionMode.webvpn,
  warnings: const <String>[],
  expiresAt: DateTime.now().add(const Duration(minutes: 2)),
  requestDigest: 'digest',
);

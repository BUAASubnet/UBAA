part of '../app_controller_test.dart';

void _registerOverviewTests() {
  test('评教固定路线回读保留overview且专用失败仍清空', () async {
    const overview = EvaluationProgressOverview(
      totalCourses: 3,
      evaluatedCourses: 3,
      pendingCourses: 0,
    );
    final backend = _EvaluationOverviewBackend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.refreshEvaluationAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );
    expect(
      controller.snapshots[FeatureId.evaluation]!.overview,
      same(overview),
    );
    backend.fail = true;
    await controller.refreshEvaluationAfterWrite(
      expectedRoute: ConnectionMode.direct,
    );
    expect(
      controller.snapshots[FeatureId.evaluation]!.status,
      FeatureLoadStatus.failure,
    );
    expect(controller.snapshots[FeatureId.evaluation]!.overview, isNull);
  });
  test('显式鉴权权限失败不保留旧overview或动作', () async {
    for (final code in [
      UbaaErrorCode.authenticationRequired,
      UbaaErrorCode.permissionDenied,
    ]) {
      var fail = false;
      final controller = AppController(
        backend: _QueryBackend(
          onQuery: (_, __) => fail
              ? FeatureResult.failure(UbaaErrorMapper.fromCode(code))
              : const FeatureResult.success(
                  overview: SpocTermOverview(termCode: 'old'),
                ),
        ),
      );
      await controller.refreshFeatureQuery(
        FeatureId.spoc,
        const FeatureQuery(),
      );
      fail = true;
      await controller.refreshFeatureQuery(
        FeatureId.spoc,
        const FeatureQuery(),
      );
      expect(
        controller.snapshots[FeatureId.spoc]!.status,
        FeatureLoadStatus.failure,
      );
      expect(controller.snapshots[FeatureId.spoc]!.overview, isNull);
      controller.dispose();
    }
  });
  for (final throwsError in [false, true]) {
    test('只有overview的数据同query异常保留stale，失败方式$throwsError', () async {
      var fail = false;
      final controller = AppController(
        backend: _QueryBackend(
          onQuery: (_, __) {
            if (fail) {
              if (throwsError)
                throw const BackendException(UbaaErrorCode.networkError);
              return FeatureResult.failure(
                UbaaErrorMapper.fromCode(UbaaErrorCode.networkError),
              );
            }
            return const FeatureResult.empty(
              overview: EvaluationProgressOverview(
                totalCourses: 7,
                evaluatedCourses: 7,
                pendingCourses: 0,
              ),
            );
          },
        ),
      );
      addTearDown(controller.dispose);
      const q = FeatureQuery(view: FeatureQueryView.evaluationPending);
      await controller.refreshFeatureQuery(FeatureId.evaluation, q);
      expect(
        controller.snapshots[FeatureId.evaluation]!.overview,
        isA<EvaluationProgressOverview>(),
      );
      fail = true;
      await controller.refreshFeatureQuery(FeatureId.evaluation, q);
      expect(
        controller.snapshots[FeatureId.evaluation]!.status,
        FeatureLoadStatus.stale,
      );
      expect(
        (controller.snapshots[FeatureId.evaluation]!.overview!
                as EvaluationProgressOverview)
            .totalCourses,
        7,
      );
    });
  }
  test('新query立即清集合统计，普通空结果缺值不沿用旧统计', () async {
    var empty = false;
    final controller = AppController(
      backend: _QueryBackend(
        onQuery: (_, __) => empty
            ? const FeatureResult.empty()
            : const FeatureResult.success(
                overview: SpocTermOverview(termCode: 'term-A'),
              ),
      ),
    );
    addTearDown(controller.dispose);
    const q = FeatureQuery();
    await controller.refreshFeatureQuery(FeatureId.spoc, q);
    final pending = controller.refreshFeatureQuery(
      FeatureId.spoc,
      const FeatureQuery(view: FeatureQueryView.spocDetail, assignmentId: 'B'),
    );
    expect(controller.snapshots[FeatureId.spoc]!.overview, isNull);
    await pending;
    empty = true;
    await controller.refreshFeatureQuery(
      FeatureId.spoc,
      const FeatureQuery(view: FeatureQueryView.spocDetail, assignmentId: 'B'),
    );
    expect(controller.snapshots[FeatureId.spoc]!.overview, isNull);
  });
}

class _EvaluationOverviewBackend extends _EvaluationBackendBase
    implements EvaluationSubmissionReadbackBackend {
  bool fail = false;
  @override
  Future<FeatureResult> loadEvaluationOnRoute({
    required ConnectionMode route,
  }) async => fail
      ? FeatureResult.failure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.networkError),
        )
      : FeatureResult.empty(
          resolvedRoute: route,
          overview: const EvaluationProgressOverview(
            totalCourses: 3,
            evaluatedCourses: 3,
            pendingCourses: 0,
          ),
        );
}

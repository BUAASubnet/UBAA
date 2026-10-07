import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/controller/evaluation.dart'
    show FixtureEvaluationBackend, FixtureEvaluationBackendBase;
import '../../support/controller/fakes.dart'
    show FixtureDiscardingWriteBackendFake;

void _registerEvaluationTests() {
  test('评教 prepare 只传递规范化 typed targets 并保持顺序', () async {
    final backend = FixtureEvaluationBackend();
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
    final backend = FixtureEvaluationBackend();
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
    final complete = AppController(backend: FixtureEvaluationBackend());
    final writeOnly = AppController(
      backend: FixtureEvaluationWriteOnlyBackend(),
    );
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
    final backend = FixtureEvaluationBackend(
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
    final cases = <FixtureEvaluationBackend>[
      FixtureEvaluationBackend(readbackError: UbaaErrorCode.networkError),
      FixtureEvaluationBackend(
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

class FixtureEvaluationWriteOnlyBackend extends FixtureEvaluationBackendBase
    with FixtureDiscardingWriteBackendFake
    implements EvaluationWriteBackend {
  @override
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationSubmitTarget> targets,
  ) async => fixtureEvaluationIntent();

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async =>
      const WriteCommitResult(
        operation: WriteOperation.evaluationSubmitCourses,
        success: true,
        message: '已提交',
        outcomeUnknown: false,
      );
}

class _EvaluationReadbackOnlyBackend extends FixtureEvaluationBackendBase
    implements EvaluationSubmissionReadbackBackend {
  @override
  Future<FeatureResult> loadEvaluationOnRoute({
    required ConnectionMode route,
  }) async => const FeatureResult.empty();
}

WriteIntent fixtureEvaluationIntent() => WriteIntent(
  intentId: 'evaluation-intent',
  operation: WriteOperation.evaluationSubmitCourses,
  targetSummary: '教学评教',
  resolvedRoute: ConnectionMode.webvpn,
  warnings: const <String>[],
  expiresAt: DateTime.now().add(const Duration(minutes: 2)),
  requestDigest: 'digest',
);

void main() {
  _registerEvaluationTests();
}

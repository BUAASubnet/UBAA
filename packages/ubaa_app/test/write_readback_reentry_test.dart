import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  for (final (operation, feature) in <(WriteOperation, FeatureId)>[
    (WriteOperation.bykcSelectCourse, FeatureId.bykc),
    (WriteOperation.libbookReserve, FeatureId.libbook),
    (WriteOperation.evaluationSubmitCourses, FeatureId.evaluation),
  ]) {
    for (final logout in <bool>[true, false]) {
      test('${operation.title}回读通知中同步${logout ? '注销' : '切换路线'}后不发请求', () async {
        final backend = _ReadbackBackend(operation);
        final controller = AppController(backend: backend);
        addTearDown(controller.dispose);
        final coordinator = controller.writeCoordinator;
        coordinator.setIntent(_intent(operation));
        var transitioned = false;
        Future<void>? transition;
        controller.addListener(() {
          if (transitioned ||
              controller.snapshots[feature]!.status !=
                  FeatureLoadStatus.loading) {
            return;
          }
          transitioned = true;
          transition = logout
              ? controller.logout()
              : controller.setRoutePolicy(RoutePolicy.webvpn);
        });

        final outcome = await coordinator.confirmForUi();
        await transition;

        expect(transitioned, isTrue);
        expect(backend.commits, 1);
        expect(backend.reads, 0);
        expect(outcome, isNull);
        expect(controller.snapshots[feature]!.summary, isNot('旧写回读'));
      });
    }
  }
}

WriteIntent _intent(WriteOperation operation) => WriteIntent(
  intentId: '测试意图',
  operation: operation,
  targetSummary: '测试目标',
  resolvedRoute: ConnectionMode.direct,
  warnings: const <String>[],
  expiresAt: DateTime.now().add(const Duration(minutes: 2)),
  requestDigest: '测试摘要',
);

class _ReadbackBackend
    implements
        UbaaBackend,
        WriteCommitBackend,
        FeatureQueryBackend,
        EvaluationSubmissionReadbackBackend {
  _ReadbackBackend(this.operation);

  final WriteOperation operation;
  var commits = 0;
  var reads = 0;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async => null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commits++;
    return WriteCommitResult(
      operation: operation,
      success: true,
      message: '提交完成',
      outcomeUnknown: false,
      resolvedRoute: ConnectionMode.direct,
    );
  }

  @override
  Future<void> discardWriteIntent(String intentId) async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async => _read();

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async => _read();

  @override
  Future<FeatureResult> loadEvaluationOnRoute({
    required ConnectionMode route,
  }) async => _read();

  FeatureResult _read() {
    reads++;
    return const FeatureResult.success(
      summary: '旧写回读',
      resolvedRoute: ConnectionMode.direct,
    );
  }
}

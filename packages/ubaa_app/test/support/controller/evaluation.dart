import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../features/evaluation/controller_test.dart'
    show FixtureEvaluationWriteOnlyBackend, fixtureEvaluationIntent;

abstract class FixtureEvaluationBackendBase implements UbaaBackend {
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

class FixtureEvaluationBackend extends FixtureEvaluationWriteOnlyBackend
    implements EvaluationSubmissionReadbackBackend {
  FixtureEvaluationBackend({
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
    return fixtureEvaluationIntent();
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

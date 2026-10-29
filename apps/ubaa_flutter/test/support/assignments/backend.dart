import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

part 'data.dart';

/// 仅供原生测试的合成数据，不访问FRB、网络或真实账号。
class CourseworkBackend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        RouteSettingsBackend,
        SigninWriteBackend,
        EvaluationWriteBackend,
        EvaluationSubmissionReadbackBackend {
  CourseworkBackend({this.state = 'normal'});
  final String state;
  bool signedIn = false;
  final reads = <(FeatureId, FeatureQuery)>[];
  final _defaultReads = <bool>[];
  final preparedSignin = <String>[];
  final preparedEvaluation = <List<EvaluationSubmitTarget>>[];
  final discarded = <String>[];
  int commitCalls = 0;
  bool _holdNext = false;
  Completer<void>? _pendingRead;
  void holdNextRead() {
    _holdNext = true;
  }

  void releaseRead() {
    final pending = _pendingRead;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  bool get hasPendingRead => _pendingRead != null && !_pendingRead!.isCompleted;
  @override
  Future<AuthStatus> authStatus() async =>
      signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;
  @override
  Future<UserSummary?> userInfo() async => signedIn
      ? const UserSummary(username: 'coursework-fixture', displayName: '合成作业同学')
      : null;
  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}
  @override
  Future<void> login(LoginInput input) async {
    signedIn = true;
  }

  @override
  Future<void> logout() async {
    signedIn = false;
  }

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: RoutePolicy.auto,
    activeRoutes: signedIn ? [ConnectionMode.direct] : [],
  );
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) =>
      _read(feature, const FeatureQuery(), defaultRead: true);
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) => _read(feature, query);

  Future<FeatureResult> _read(
    FeatureId feature,
    FeatureQuery query, {
    bool defaultRead = false,
  }) async {
    if (!signedIn) {
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    var count = 0;
    for (var i = 0; i < reads.length; i++) {
      if (_defaultReads[i] == defaultRead &&
          reads[i].$1 == feature &&
          reads[i].$2.hasSameParameters(query)) {
        count++;
      }
    }
    reads.add((
      feature,
      query.copyWith(judgeKeys: List.unmodifiable(query.judgeKeys)),
    ));
    _defaultReads.add(defaultRead);
    if (state == 'loading' && _holdNext) {
      _holdNext = false;
      final gate = Completer<void>();
      _pendingRead = gate;
      await gate.future;
      if (identical(_pendingRead, gate)) _pendingRead = null;
    }
    if ((state == 'first-error' && count == 0) ||
        (state == 'stale' && count > 0)) {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    return _courseworkData(this, feature, query);
  }

  @override
  Future<FeatureResult> loadEvaluationOnRoute({
    required ConnectionMode route,
  }) => loadFeature(FeatureId.evaluation);
  @override
  Future<WriteIntent> prepareSigninPerform({required String courseId}) async {
    preparedSignin.add(courseId);
    return _intent(WriteOperation.signinPerform, courseId);
  }

  @override
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationSubmitTarget> targets,
  ) async {
    preparedEvaluation.add(List.unmodifiable(targets));
    return _intent(WriteOperation.evaluationSubmitCourses, '合成评教目标');
  }

  WriteIntent _intent(WriteOperation operation, String summary) => WriteIntent(
    intentId:
        'coursework-${preparedSignin.length}-${preparedEvaluation.length}',
    operation: operation,
    targetSummary: summary,
    resolvedRoute: ConnectionMode.direct,
    warnings: const ['合成测试仅准备与取消，不提交'],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'synthetic-digest',
  );
  @override
  Future<void> discardWriteIntent(String intentId) async {
    discarded.add(intentId);
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    throw StateError('本测试不允许提交写入');
  }
}

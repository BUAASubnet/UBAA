import 'dart:async';

import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'recovery.dart' as support;

WriteIntent _intent() => WriteIntent(
  intentId: 'synthetic',
  operation: WriteOperation.bykcSelectCourse,
  targetSummary: '合成目标',
  resolvedRoute: ConnectionMode.direct,
  warnings: const [],
  expiresAt: DateTime.now().add(const Duration(minutes: 2)),
  requestDigest: 'synthetic',
);

class SyntheticWriteCacheBackend extends support.FakeRecoveryBackend
    implements
        CacheWriteBackend,
        BykcWriteBackend,
        ProgressiveReadBackend,
        FeatureQueryBackend,
        BykcReadbackBackend {
  int prepares = 0;
  @override
  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) async {
    if (courseId != 42)
      throw const BackendException(UbaaErrorCode.invalidInput);
    prepares++;
    return _intent();
  }

  @override
  Future<WriteIntent> prepareBykcDeselectCourse({
    required int courseId,
  }) async => throw const BackendException(UbaaErrorCode.unsupported);
  @override
  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) async => throw const BackendException(UbaaErrorCode.unsupported);
  int cachedCommits = 0,
      ordinaryCommits = 0,
      readbacks = 0,
      postCommitQueries = 0;
  bool unknown = false, success = true, failRefresh = false;
  Completer<WriteCommitResult>? commitGate;
  String? account, expectedAccount;
  final readback = Completer<FeatureResult>();
  @override
  Future<void> discardWriteIntent(String intentId) async {}
  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    ordinaryCommits++;
    return _result;
  }

  @override
  Future<WriteCommitResult> commitWriteWithCache(
    String intentId, {
    required String accountId,
  }) async {
    cachedCommits++;
    account = accountId;
    if (commitGate case final gate?) return gate.future;
    if (unknown)
      throw const BackendException(
        UbaaErrorCode.outcomeUnknown,
        resolvedRoute: ConnectionMode.direct,
        cacheFailure: CacheMaintenanceFailure.corrupt,
      );
    return _result;
  }

  WriteCommitResult get _result => WriteCommitResult(
    operation: WriteOperation.bykcSelectCourse,
    success: success,
    message: '合成成功',
    outcomeUnknown: false,
    resolvedRoute: ConnectionMode.direct,
  );
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) =>
      feature == FeatureId.bykc
      ? loadFeatureQuery(feature, const FeatureQuery())
      : super.loadFeature(feature);

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;
  @override
  Future<FeatureResult> readBykcAfterWrite(FeatureQuery query) {
    readbacks++;
    return readback.future;
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (cachedCommits + ordinaryCommits > 0) postCommitQueries++;
    if (postCommitQueries > 0 && failRefresh)
      throw const BackendException(UbaaErrorCode.networkError);
    return FeatureResult.success(
      resolvedRoute: ConnectionMode.direct,
      details: [
        FeatureDetail(
          title: feature == FeatureId.bykc ? '合成课程' : '无关课表',
          fields: feature == FeatureId.bykc
              ? const [FeatureField(label: '课程 ID', value: '42')]
              : const [],
          actions: feature == FeatureId.bykc
              ? const [
                  BykcSelectAction(
                    courseId: 42,
                    eligibility: ActionEligibility.allowed,
                  ),
                ]
              : const [],
        ),
      ],
    );
  }
}

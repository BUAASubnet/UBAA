part of '../ubaa_app_host_test.dart';

PlatformCapabilities _capabilities() => PlatformCapabilities(
  credentialVault: MemoryCredentialVault(),
  photoPicker: MemoryPhotoPicker(),
  permissionGateway: MemoryPermissionGateway(),
  locationProvider: const UnavailableLocationProvider(),
);

const _safeHostPhoto = YgdkPhotoInput(
  bytes: <int>[1, 2, 3],
  fileName: 'safe.jpg',
  mimeType: 'image/jpeg',
);

class _HostReadOnlyBackend implements UbaaBackend {
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

final class _HostYgdkWriteOnlyBackend extends _HostReadOnlyBackend
    implements YgdkWriteBackend {
  @override
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input) async =>
      _hostYgdkIntent;

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async =>
      const WriteCommitResult(
        operation: WriteOperation.ygdkSubmit,
        success: true,
        message: '不应使用',
        outcomeUnknown: false,
      );

  @override
  Future<void> discardWriteIntent(String intentId) async {}
}

final class _HostYgdkReadbackOnlyBackend extends _HostReadOnlyBackend
    implements YgdkSubmissionReadbackBackend {
  @override
  Future<FeatureResult> loadYgdkOverviewOnRoute({
    required ConnectionMode route,
  }) async => const FeatureResult.empty();

  @override
  Future<FeatureResult> loadYgdkRecordsOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) async => const FeatureResult.empty();
}

final class _HostEvaluationWriteOnlyBackend extends _HostReadOnlyBackend
    implements EvaluationWriteBackend {
  @override
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationSubmitTarget> targets,
  ) async => _hostEvaluationIntent;

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async =>
      const WriteCommitResult(
        operation: WriteOperation.evaluationSubmitCourses,
        success: true,
        message: '不应使用',
        outcomeUnknown: false,
      );

  @override
  Future<void> discardWriteIntent(String intentId) async {}
}

final class _HostEvaluationReadbackOnlyBackend extends _HostReadOnlyBackend
    implements EvaluationSubmissionReadbackBackend {
  @override
  Future<FeatureResult> loadEvaluationOnRoute({
    required ConnectionMode route,
  }) async => FeatureResult.empty(resolvedRoute: route);
}

final _hostYgdkIntent = WriteIntent(
  intentId: 'host-ygdk-intent',
  operation: WriteOperation.ygdkSubmit,
  targetSummary: '阳光打卡',
  resolvedRoute: ConnectionMode.direct,
  warnings: const <String>[],
  expiresAt: DateTime.utc(2099),
  requestDigest: 'digest',
);

final _hostEvaluationIntent = WriteIntent(
  intentId: 'host-evaluation-intent',
  operation: WriteOperation.evaluationSubmitCourses,
  targetSummary: '教学评教',
  resolvedRoute: ConnectionMode.direct,
  warnings: const <String>[],
  expiresAt: DateTime.utc(2099),
  requestDigest: 'digest',
);

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

PlatformCapabilities fixtureCapabilities() => PlatformCapabilities(
  credentialVault: MemoryCredentialVault(),
  photoPicker: MemoryPhotoPicker(),
  permissionGateway: MemoryPermissionGateway(),
  locationProvider: const UnavailableLocationProvider(),
);

const fixtureSafeHostPhoto = YgdkPhotoInput(
  bytes: <int>[1, 2, 3],
  fileName: 'safe.jpg',
  mimeType: 'image/jpeg',
);

class FixtureHostReadOnlyBackend implements UbaaBackend {
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

final class FixtureHostYgdkWriteOnlyBackend extends FixtureHostReadOnlyBackend
    implements YgdkWriteBackend {
  @override
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input) async =>
      fixtureHostYgdkIntent;

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

final class FixtureHostYgdkReadbackOnlyBackend
    extends FixtureHostReadOnlyBackend
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

final class FixtureHostEvaluationWriteOnlyBackend
    extends FixtureHostReadOnlyBackend
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

final class FixtureHostEvaluationReadbackOnlyBackend
    extends FixtureHostReadOnlyBackend
    implements EvaluationSubmissionReadbackBackend {
  @override
  Future<FeatureResult> loadEvaluationOnRoute({
    required ConnectionMode route,
  }) async => FeatureResult.empty(resolvedRoute: route);
}

final fixtureHostYgdkIntent = WriteIntent(
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

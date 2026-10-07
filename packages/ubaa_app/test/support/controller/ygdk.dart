import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

class FixtureYgdkReadbackBackend
    implements UbaaBackend, YgdkSubmissionReadbackBackend {
  FixtureYgdkReadbackBackend({
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

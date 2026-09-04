part of '../app_controller_test.dart';

final class _RefreshMatrixBackend implements UbaaBackend, FeatureQueryBackend {
  final List<FeatureId> loadedFeatures = <FeatureId>[];
  final List<(FeatureId, FeatureQuery)> queries = <(FeatureId, FeatureQuery)>[];

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
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    loadedFeatures.add(feature);
    return FeatureResult.success(
      summary: feature.title,
      details: <FeatureDetail>[FeatureDetail(title: feature.title)],
    );
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    queries.add((feature, query));
    return FeatureResult.success(
      summary: feature.title,
      details: <FeatureDetail>[FeatureDetail(title: feature.title)],
    );
  }
}

class _FlakyBackend implements UbaaBackend {
  _FlakyBackend({required this.load});

  final Future<FeatureResult> Function(FeatureId) load;

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
  Future<FeatureResult> loadFeature(FeatureId feature) => load(feature);
}

class _DelayedFeatureBackend implements UbaaBackend {
  final Completer<void> loadStarted = Completer<void>();
  final Completer<FeatureResult> releaseLoad = Completer<FeatureResult>();

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
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    loadStarted.complete();
    return releaseLoad.future;
  }
}

class _QueryBackend implements UbaaBackend, FeatureQueryBackend {
  _QueryBackend({required this.onQuery});

  final FeatureResult Function(FeatureId, FeatureQuery) onQuery;

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
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async => onQuery(feature, query);
}

class _RouteStateBackend implements UbaaBackend, RouteSettingsBackend {
  _RouteStateBackend({required this.activeRoutes});

  final List<ConnectionMode> activeRoutes;
  RoutePolicy defaultPolicy = RoutePolicy.auto;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'student');

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {
    defaultPolicy = policy;
  }

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: defaultPolicy,
    activeRoutes: activeRoutes,
  );
}

class _RebuildBackend
    implements UbaaBackend, RouteSettingsBackend, BackendLifecycle {
  _RebuildBackend({required this.signedIn, required this.activeRoutes});

  final bool signedIn;
  final List<ConnectionMode> activeRoutes;
  bool disposed = false;
  int disposeCalls = 0;

  @override
  Future<AuthStatus> authStatus() async =>
      signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async =>
      signedIn ? const UserSummary(username: 'student') : null;

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
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: RoutePolicy.auto,
    activeRoutes: activeRoutes,
  );

  @override
  Future<void> dispose() async {
    disposeCalls++;
    disposed = true;
  }
}

class _BlockingDisposeBackend extends _RebuildBackend {
  _BlockingDisposeBackend()
    : super(signedIn: false, activeRoutes: const <ConnectionMode>[]);

  final Completer<void> disposeStarted = Completer<void>();
  final Completer<void> releaseDispose = Completer<void>();

  @override
  Future<void> dispose() async {
    disposeCalls++;
    disposed = true;
    if (!disposeStarted.isCompleted) disposeStarted.complete();
    await releaseDispose.future;
  }
}

class _DelayedInitializeBackend implements UbaaBackend, BackendLifecycle {
  final Completer<void> authStarted = Completer<void>();
  final Completer<void> releaseAuth = Completer<void>();
  bool disposed = false;

  @override
  Future<AuthStatus> authStatus() async {
    authStarted.complete();
    await releaseAuth.future;
    return AuthStatus.signedOut;
  }

  @override
  Future<UserSummary?> userInfo() async => null;

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
  Future<void> dispose() async {
    disposed = true;
  }
}

class _DelayedSignedInInitializeBackend
    implements UbaaBackend, BackendLifecycle {
  final Completer<void> authStarted = Completer<void>();
  final Completer<void> releaseAuth = Completer<void>();
  int userInfoCalls = 0;
  int featureLoads = 0;

  @override
  Future<AuthStatus> authStatus() async {
    authStarted.complete();
    await releaseAuth.future;
    return AuthStatus.signedIn;
  }

  @override
  Future<UserSummary?> userInfo() async {
    userInfoCalls++;
    return const UserSummary(username: 'student');
  }

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    featureLoads++;
    return const FeatureResult.empty();
  }

  @override
  Future<void> dispose() async {}
}

class _DelayedLoginBackend implements UbaaBackend, BackendLifecycle {
  final Completer<void> loginStarted = Completer<void>();
  final Completer<void> releaseLogin = Completer<void>();
  int userInfoCalls = 0;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async {
    userInfoCalls++;
    return const UserSummary(username: 'student');
  }

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {
    loginStarted.complete();
    await releaseLogin.future;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<void> dispose() async {}
}

class _DelayedRoutePolicyBackend
    implements UbaaBackend, RouteSettingsBackend, BackendLifecycle {
  final Completer<void> prepareStarted = Completer<void>();
  final Completer<void> releasePrepare = Completer<void>();
  int routeSettingsCalls = 0;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async => null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {
    prepareStarted.complete();
    await releasePrepare.future;
  }

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<BackendRouteSettings> routeSettings() async {
    routeSettingsCalls++;
    return const BackendRouteSettings(
      defaultPolicy: RoutePolicy.webvpn,
      activeRoutes: <ConnectionMode>[],
    );
  }

  @override
  Future<void> dispose() async {}
}

class _DelayedLogoutBackend implements UbaaBackend, BackendLifecycle {
  final Completer<void> logoutStarted = Completer<void>();
  final Completer<void> releaseLogout = Completer<void>();

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
  Future<void> logout() async {
    logoutStarted.complete();
    await releaseLogout.future;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<void> dispose() async {}
}

class _BykcWriteBackend
    implements UbaaBackend, BykcWriteBackend, WriteIntentDiscardBackend {
  int? selectedCourseId;
  int? signCourseId;
  int? signType;
  double? signLat;
  double? signLng;
  String? discardedIntentId;
  int commitCalls = 0;
  final List<FeatureId> loadedFeatures = <FeatureId>[];

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
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    loadedFeatures.add(feature);
    return const FeatureResult.empty();
  }

  @override
  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) async {
    selectedCourseId = courseId;
    return _intent(WriteOperation.bykcSelectCourse);
  }

  @override
  Future<WriteIntent> prepareBykcDeselectCourse({required int courseId}) async {
    selectedCourseId = courseId;
    return _intent(WriteOperation.bykcDeselectCourse);
  }

  @override
  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) async {
    this.signCourseId = courseId;
    this.signType = signType;
    signLat = lat;
    signLng = lng;
    return _intent(WriteOperation.bykcSignCourse);
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    return const WriteCommitResult(
      operation: WriteOperation.bykcSelectCourse,
      success: true,
      message: 'ok',
      outcomeUnknown: false,
    );
  }

  @override
  Future<void> discardWriteIntent(String intentId) async {
    discardedIntentId = intentId;
  }

  WriteIntent _intent(WriteOperation operation) => WriteIntent(
    intentId: 'intent-${selectedCourseId ?? 0}',
    operation: operation,
    targetSummary: '课程 ${selectedCourseId ?? 0}',
    resolvedRoute: ConnectionMode.direct,
    warnings: const <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
}

class _CommitCapabilityBackend implements UbaaBackend, WriteCommitBackend {
  String? discardedIntentId;

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
  Future<WriteCommitResult> commitWrite(String intentId) async =>
      const WriteCommitResult(
        operation: WriteOperation.bykcSelectCourse,
        success: true,
        message: 'ok',
        outcomeUnknown: false,
      );

  @override
  Future<void> discardWriteIntent(String intentId) async {
    discardedIntentId = intentId;
  }
}

mixin _DiscardingWriteBackendFake implements WriteIntentDiscardBackend {
  @override
  Future<void> discardWriteIntent(String intentId) async {}
}

class _SigninWriteBackend
    with _DiscardingWriteBackendFake
    implements UbaaBackend, SigninWriteBackend {
  String? courseId;
  int commitCalls = 0;

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
  Future<WriteIntent> prepareSigninPerform({required String courseId}) async {
    this.courseId = courseId;
    return _intent();
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    return const WriteCommitResult(
      operation: WriteOperation.signinPerform,
      success: true,
      message: 'ok',
      outcomeUnknown: false,
    );
  }

  WriteIntent _intent() => WriteIntent(
    intentId: 'signin-intent',
    operation: WriteOperation.signinPerform,
    targetSummary: '课程 ${courseId ?? ''}',
    resolvedRoute: ConnectionMode.direct,
    warnings: const <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
}

class _CancellationWriteBackend
    with _DiscardingWriteBackendFake
    implements UbaaBackend, CancellationWriteBackend {
  String? bookingId;
  int? orderId;

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
  Future<WriteIntent> prepareLibbookCancelBooking({required String id}) async {
    bookingId = id;
    return _intent(WriteOperation.libbookCancelBooking, id);
  }

  @override
  Future<WriteIntent> prepareCgyyCancelOrder({required int id}) async {
    orderId = id;
    return _intent(WriteOperation.cgyyCancelOrder, '$id');
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async =>
      const WriteCommitResult(
        operation: WriteOperation.libbookCancelBooking,
        success: true,
        message: 'ok',
        outcomeUnknown: false,
      );

  WriteIntent _intent(WriteOperation operation, String target) => WriteIntent(
    intentId: 'cancel-intent',
    operation: operation,
    targetSummary: '取消 $target',
    resolvedRoute: ConnectionMode.direct,
    warnings: const <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
}

class _LibbookWriteBackend
    with _DiscardingWriteBackendFake
    implements UbaaBackend, LibbookWriteBackend {
  int prepareCalls = 0;
  String? areaId;
  String? seatId;
  String? day;
  String? segment;
  String? startTime;
  String? endTime;

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
  Future<WriteIntent> prepareLibbookReserve({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  }) async {
    prepareCalls++;
    this.areaId = areaId;
    this.seatId = seatId;
    this.day = day;
    this.segment = segment;
    this.startTime = startTime;
    this.endTime = endTime;
    return WriteIntent(
      intentId: 'reserve-intent',
      operation: WriteOperation.libbookReserve,
      targetSummary: '$areaId/$seatId $day $segment',
      resolvedRoute: ConnectionMode.direct,
      warnings: const <String>[],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'digest',
    );
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async =>
      const WriteCommitResult(
        operation: WriteOperation.libbookReserve,
        success: true,
        message: 'ok',
        outcomeUnknown: false,
      );
}

class _YgdkWriteBackend
    with _DiscardingWriteBackendFake
    implements UbaaBackend, YgdkWriteBackend {
  YgdkSubmitInput? input;
  int commitCalls = 0;

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
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input) async {
    this.input = input;
    return _intent();
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    return const WriteCommitResult(
      operation: WriteOperation.ygdkSubmit,
      success: true,
      message: 'ok',
      outcomeUnknown: false,
    );
  }

  WriteIntent _intent() => WriteIntent(
    intentId: 'ygdk-intent',
    operation: WriteOperation.ygdkSubmit,
    targetSummary: '阳光打卡',
    resolvedRoute: ConnectionMode.direct,
    warnings: <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
}

class _CgyyWriteBackend
    with _DiscardingWriteBackendFake
    implements UbaaBackend, CgyyWriteBackend {
  CgyySubmitInput? input;
  int commitCalls = 0;

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
  Future<WriteIntent> prepareCgyySubmitReservation(
    CgyySubmitInput input,
  ) async {
    this.input = input;
    return _intent();
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    return const WriteCommitResult(
      operation: WriteOperation.cgyySubmitReservation,
      success: true,
      message: 'ok',
      outcomeUnknown: false,
    );
  }

  WriteIntent _intent() => WriteIntent(
    intentId: 'cgyy-intent',
    operation: WriteOperation.cgyySubmitReservation,
    targetSummary: '场馆预约',
    resolvedRoute: ConnectionMode.direct,
    warnings: <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
}

class _CgyyQueryWriteBackend extends _CgyyWriteBackend
    implements FeatureQueryBackend {
  _CgyyQueryWriteBackend({this.queryResult = const FeatureResult.empty()});

  final FeatureResult queryResult;
  final List<(FeatureId, FeatureQuery)> queries = <(FeatureId, FeatureQuery)>[];

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    queries.add((feature, query));
    return queryResult;
  }
}

class _EvaluationWriteBackend
    with _DiscardingWriteBackendFake
    implements UbaaBackend, EvaluationWriteBackend {
  List<EvaluationCourseInput> courses = const <EvaluationCourseInput>[];
  int commitCalls = 0;

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
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationCourseInput> courses,
  ) async {
    this.courses = courses;
    return _intent();
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    return const WriteCommitResult(
      operation: WriteOperation.evaluationSubmitCourses,
      success: true,
      message: 'ok',
      outcomeUnknown: false,
    );
  }

  WriteIntent _intent() => WriteIntent(
    intentId: 'evaluation-intent',
    operation: WriteOperation.evaluationSubmitCourses,
    targetSummary: '教学评教',
    resolvedRoute: ConnectionMode.direct,
    warnings: <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
}

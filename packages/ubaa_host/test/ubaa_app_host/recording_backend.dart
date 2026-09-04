part of '../ubaa_app_host_test.dart';

final class _RecordingBackend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        CgyyCancellationReadbackBackend,
        YgdkSubmissionReadbackBackend,
        RouteSettingsBackend,
        BykcWriteBackend,
        SigninWriteBackend,
        CancellationWriteBackend,
        LibbookWriteBackend,
        YgdkWriteBackend,
        CgyyWriteBackend,
        EvaluationWriteBackend,
        WriteIntentDiscardBackend,
        BackendLifecycle {
  static const commitResult = WriteCommitResult(
    operation: WriteOperation.cgyySubmitReservation,
    success: true,
    message: 'commit-result-41997',
    outcomeUnknown: false,
    resolvedRoute: ConnectionMode.webvpn,
    cgyyReceipt: CgyyReservationReceipt(orderId: 41999),
  );

  bool signedIn = false;
  RoutePolicy routePolicy = RoutePolicy.auto;
  LoginInput? lastLogin;
  final List<FeatureId> loadedFeatures = <FeatureId>[];
  final List<({FeatureId feature, FeatureQuery query})> queryCalls =
      <({FeatureId feature, FeatureQuery query})>[];
  final List<ConnectionMode> ygdkOverviewRoutes = <ConnectionMode>[];
  final List<({ConnectionMode route, int page, int size})> ygdkRecordReads =
      <({ConnectionMode route, int page, int size})>[];
  int? bykcSelectCourseId;
  int? bykcDeselectCourseId;
  ({int courseId, double? lat, double? lng, int signType})? bykcSign;
  String? signinCourseId;
  String? libbookCancellationId;
  int? libbookCancellationPage;
  int? libbookCancellationLimit;
  int? cgyyCancellationId;
  ({
    String areaId,
    String seatId,
    String day,
    String segment,
    String startTime,
    String endTime,
  })?
  libbookReservation;
  YgdkSubmitInput? ygdkInput;
  CgyySubmitInput? cgyyInput;
  List<EvaluationCourseInput>? evaluationCourses;
  String? committedIntentId;
  String? discardedIntentId;
  Object? commitFailure;
  int logoutCalls = 0;
  int disposeCalls = 0;

  void resetReadCalls() {
    loadedFeatures.clear();
    queryCalls.clear();
    ygdkOverviewRoutes.clear();
    ygdkRecordReads.clear();
  }

  @override
  Future<AuthStatus> authStatus() async =>
      signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async => signedIn
      ? const UserSummary(username: 'student-fixture', displayName: '测试同学')
      : null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {
    routePolicy = policy;
  }

  @override
  Future<void> login(LoginInput input) async {
    lastLogin = input;
    signedIn = true;
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    signedIn = false;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    loadedFeatures.add(feature);
    return FeatureResult.success(summary: '脱敏 ${feature.title}');
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    queryCalls.add((feature: feature, query: query));
    if (feature == FeatureId.cgyy &&
        query.view == FeatureQueryView.cgyyOrders) {
      return const FeatureResult.success(
        summary: '脱敏场馆订单',
        resolvedRoute: ConnectionMode.direct,
        details: <FeatureDetail>[
          FeatureDetail(
            title: '脱敏订单',
            fields: <FeatureField>[FeatureField(label: '订单编号', value: '41999')],
          ),
          FeatureDetail(
            title: '已取消订单',
            actions: <FeatureAction>[
              CgyyCancelAction(
                orderId: 41006,
                orderStatus: 2,
                checkStatus: 2,
                targetOrderId: null,
                cancelledTargetOrderId: 41006,
                eligibility: ActionEligibility.denied,
              ),
            ],
          ),
        ],
      );
    }
    if (feature == FeatureId.cgyy &&
        query.view == FeatureQueryView.cgyyOrderDetail &&
        query.orderId == 41006) {
      return const FeatureResult.success(
        summary: '脱敏场馆订单详情',
        resolvedRoute: ConnectionMode.direct,
        details: <FeatureDetail>[
          FeatureDetail(
            title: '已取消订单',
            actions: <FeatureAction>[
              CgyyCancelAction(
                orderId: 41006,
                orderStatus: 2,
                checkStatus: 2,
                targetOrderId: null,
                cancelledTargetOrderId: 41006,
                eligibility: ActionEligibility.denied,
              ),
            ],
          ),
        ],
      );
    }
    return FeatureResult.success(summary: '脱敏 ${feature.title}');
  }

  @override
  Future<FeatureResult> loadCgyyOrdersOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) => loadFeatureQuery(
    FeatureId.cgyy,
    FeatureQuery(view: FeatureQueryView.cgyyOrders, page: page, size: size),
  );

  @override
  Future<FeatureResult> loadCgyyOrderDetailOnRoute({
    required ConnectionMode route,
    required int orderId,
  }) => loadFeatureQuery(
    FeatureId.cgyy,
    FeatureQuery(view: FeatureQueryView.cgyyOrderDetail, orderId: orderId),
  );

  @override
  Future<FeatureResult> loadYgdkOverviewOnRoute({
    required ConnectionMode route,
  }) async {
    ygdkOverviewRoutes.add(route);
    return FeatureResult.success(summary: '脱敏阳光打卡概览', resolvedRoute: route);
  }

  @override
  Future<FeatureResult> loadYgdkRecordsOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) async {
    ygdkRecordReads.add((route: route, page: page, size: size));
    return FeatureResult.success(summary: '脱敏阳光打卡记录', resolvedRoute: route);
  }

  @override
  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) async {
    bykcSelectCourseId = courseId;
    return _intent('bykc-select', WriteOperation.bykcSelectCourse);
  }

  @override
  Future<WriteIntent> prepareBykcDeselectCourse({required int courseId}) async {
    bykcDeselectCourseId = courseId;
    return _intent('bykc-deselect', WriteOperation.bykcDeselectCourse);
  }

  @override
  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) async {
    bykcSign = (courseId: courseId, lat: lat, lng: lng, signType: signType);
    return _intent('bykc-sign', WriteOperation.bykcSignCourse);
  }

  @override
  Future<WriteIntent> prepareSigninPerform({required String courseId}) async {
    signinCourseId = courseId;
    return _intent('signin', WriteOperation.signinPerform);
  }

  @override
  Future<WriteIntent> prepareLibbookCancelBooking({
    required String id,
    required int page,
    required int limit,
  }) async {
    libbookCancellationId = id;
    libbookCancellationPage = page;
    libbookCancellationLimit = limit;
    return _intent(
      'libbook-cancel',
      WriteOperation.libbookCancelBooking,
    ).withReadbackQuery(
      FeatureQuery(
        view: FeatureQueryView.libbookBookings,
        page: page,
        size: limit,
      ),
    );
  }

  @override
  Future<WriteIntent> prepareCgyyCancelOrder({required int id}) async {
    cgyyCancellationId = id;
    return _intent(
      'cgyy-cancel',
      WriteOperation.cgyyCancelOrder,
    ).withReadbackQuery(
      FeatureQuery(view: FeatureQueryView.cgyyOrderDetail, orderId: id),
    );
  }

  @override
  Future<WriteIntent> prepareLibbookReserve({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  }) async {
    libbookReservation = (
      areaId: areaId,
      seatId: seatId,
      day: day,
      segment: segment,
      startTime: startTime,
      endTime: endTime,
    );
    return _intent('libbook-reserve', WriteOperation.libbookReserve);
  }

  @override
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input) async {
    ygdkInput = input;
    return _intent('ygdk-submit', WriteOperation.ygdkSubmit);
  }

  @override
  Future<WriteIntent> prepareCgyySubmitReservation(
    CgyySubmitInput input,
  ) async {
    cgyyInput = input;
    return _intent('cgyy-submit', WriteOperation.cgyySubmitReservation);
  }

  @override
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationCourseInput> courses,
  ) async {
    evaluationCourses = List<EvaluationCourseInput>.unmodifiable(courses);
    return _intent('evaluation-submit', WriteOperation.evaluationSubmitCourses);
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    committedIntentId = intentId;
    final failure = commitFailure;
    if (failure != null) throw failure;
    return commitResult;
  }

  @override
  Future<void> discardWriteIntent(String intentId) async {
    discardedIntentId = intentId;
  }

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: routePolicy,
    activeRoutes: signedIn
        ? const <ConnectionMode>[ConnectionMode.direct, ConnectionMode.webvpn]
        : const <ConnectionMode>[],
  );

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  WriteIntent _intent(String id, WriteOperation operation) => WriteIntent(
    intentId: 'intent-$id',
    operation: operation,
    targetSummary: 'target-$id',
    resolvedRoute: ConnectionMode.direct,
    warnings: const <String>[],
    expiresAt: DateTime.utc(2099, 1, 1),
    requestDigest: 'digest-$id',
  );
}

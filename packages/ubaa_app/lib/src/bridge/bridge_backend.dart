import 'dart:async';
import 'write/pinned_readback.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import 'auth/session.dart'
    show
        bridgeAuthStatus,
        bridgeBeginInteractiveLogin,
        bridgeCancelInteractiveLogin,
        bridgeContinueInteractiveLogin,
        bridgeDiscardInteractiveCaptcha,
        bridgeDispose,
        bridgeLogin,
        bridgeLoginRequiredRoute,
        bridgeLogout,
        bridgePrepareLogin,
        bridgeRecoverRequiredSession,
        bridgeRefreshInteractiveCaptcha,
        bridgeRouteSettings,
        bridgeSetDefaultRoutePolicy,
        bridgeSubmitInteractiveLogin,
        bridgeUserInfo;
import 'cache/lifecycle.dart'
    show
        bridgeCacheUsage,
        bridgeClearBusinessCache,
        bridgeClearOrRebuildBusinessCache,
        bridgeOfflineSerial,
        bridgeOpenOfflineAccount,
        bridgeWithOfflineRead;
import 'features/bykc/reader.dart' show bridgeLoadBykcFeature;
import 'features/cgyy/lock_display.dart' show BridgeLockDisplaySession;
import 'features/cgyy/reader.dart'
    show
        bridgeLoadCgyyFeature,
        bridgeLoadCgyyOrderDetailOnRoute,
        bridgeLoadCgyyOrdersOnRoute;
import 'features/evaluation/reader.dart' show bridgeLoadEvaluationOnRoute;
import 'features/grades/reader.dart' show bridgeUpdateGradeScoreBaseline;
import 'features/libbook/reader.dart' show bridgeLoadLibbookFeature;
import 'features/profile/reader.dart'
    show bridgeReadCachedProfile, bridgeRefreshProfile;
import 'features/schedule/reader.dart' show bridgeBeginScheduleImport;
import 'features/signin/reader.dart' show bridgeLoadSigninHome;
import 'read/progressive.dart' show bridgeBeginProgressiveRead;
import 'features/ygdk/reader.dart'
    show bridgeLoadYgdkOverviewOnRoute, bridgeLoadYgdkRecordsOnRoute;
import 'home/reader.dart' show bridgeReadCachedHome;
import 'read/cache_query.dart' show bridgeReadCachedQuery;
import 'read/dispatch.dart' show bridgeLoadFeatureQuery;
import 'support/mapping.dart' show bridgeDateOnly;
import 'write/operations.dart'
    show
        bridgeCommitWrite,
        bridgeDiscardWriteIntent,
        bridgeDismissWriteReadbackHint,
        bridgePrepareBykcDeselectCourse,
        bridgePrepareBykcSelectCourse,
        bridgePrepareBykcSignCourse,
        bridgePrepareCgyyCancelOrder,
        bridgePrepareCgyySubmitReservation,
        bridgePrepareEvaluationSubmitCourses,
        bridgePrepareLibbookCancelBooking,
        bridgePrepareLibbookReserve,
        bridgePrepareSigninPerform,
        bridgePrepareYgdkSubmit,
        bridgeReadWriteReadbackHints;

const _supportedBridgeContractVersion = 41;

/// 基于 FRB opaque client 的生产后端。
///
/// 该适配器只负责把 bridge 的 typed 结果投影到应用层；请求 URL、Cookie、
/// Session 和路线选择仍由 Rust Core 管理。测试可以继续显式注入 [DemoBackend]，
/// 生产宿主不得把 Demo 作为默认实现。
class BridgeBackend
    implements
        UbaaBackend,
        PinnedWriteReadbackBackend,
        InteractiveLoginBackend,
        CgyyLockDisplayBackend,
        FeatureQueryBackend,
        SigninReadbackBackend,
        BykcReadbackBackend,
        LibbookReadbackBackend,
        CgyyCancellationReadbackBackend,
        CgyyReservationReadbackBackend,
        YgdkSubmissionReadbackBackend,
        EvaluationSubmissionReadbackBackend,
        BykcWriteBackend,
        SigninWriteBackend,
        CancellationWriteBackend,
        LibbookWriteBackend,
        YgdkWriteBackend,
        CgyyWriteBackend,
        EvaluationWriteBackend,
        RouteSettingsBackend,
        RequiredSessionBackend,
        OfflineCacheBackend,
        ProfileCacheBackend,
        CacheManagementBackend,
        CacheRecoveryBackend,
        CacheWriteBackend,
        WriteReadbackBackend,
        GradeScoreBaselineBackend,
        OfflineQueryBackend,
        ProgressiveReadBackend,
        AccountScopedProgressiveReadBackend,
        ScheduleImportBackend,
        BackendLifecycle {
  BridgeBackend(BridgeClient client, {String? configDirectory})
    : _context = BridgeContext(client, configDirectory: configDirectory) {
    final contractVersion = client.contractVersion();
    if (contractVersion != _supportedBridgeContractVersion) {
      _disposeIncompatibleBridgeClient(client);
      throw const InitializationException(
        InitializationFailure.bridgeIncompatible,
      );
    }
  }

  @override
  Future<CgyyLockDisplaySession> openLockDisplay() async =>
      BridgeLockDisplaySession(client, await client.openCgyyLockDisplay());

  /// 从平台已经解析好的应用私有目录打开 Core。
  static Future<BridgeBackend> open(String configDirectory) async =>
      BridgeBackend(
        await BridgeClient.open(configDir: configDirectory),
        configDirectory: configDirectory,
      );

  final BridgeContext _context;
  @override
  Future<FeatureResult> readAfterWriteOnRoute(
    WriteOperation operation, {
    required ConnectionMode route,
    FeatureQuery? query,
  }) => bridgePinnedWriteReadback(_context, operation, route, query);
  BridgeClient get client => _context.client;
  String? get configDirectory => _context.configDirectory;

  @override
  Future<CacheUsageSummary> cacheUsage({required String accountId}) =>
      bridgeCacheUsage(_context, accountId);
  @override
  Future<CacheClearOutcome> clearBusinessCache({required String accountId}) =>
      bridgeClearBusinessCache(_context, accountId);

  @override
  Future<CacheClearOutcome> clearOrRebuildBusinessCache({
    required LocalAccount account,
    required List<int> key,
  }) => bridgeClearOrRebuildBusinessCache(_context, account, key);

  @override
  Future<void> openOfflineAccount(LocalAccount account, List<int> key) =>
      bridgeOpenOfflineAccount(_context, account, key);
  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) =>
      bridgeWithOfflineRead(
        _context,
        () => bridgeReadCachedHome(_context, policy),
      );
  @override
  Future<OfflineQueryRead> readCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    RoutePolicy policy,
  ) => bridgeWithOfflineRead(
    _context,
    () => bridgeReadCachedQuery(_context, feature, query, policy),
  );
  @override
  Future<void> deactivateOfflineAccount() {
    _context.cache.generation++;
    return bridgeOfflineSerial(_context, () async {
      await _context.cache.handle?.deactivate();
    });
  }

  @override
  Future<void> clearOfflineAccount() {
    _context.cache.generation++;
    _context.cache.targetAccountId = null;
    return bridgeOfflineSerial(_context, () async {
      await _context.cache.handle?.clear();
      _context.cache.handle = null;
      _context.cache.account = null;
    });
  }

  @override
  Future<FeatureResult> readLibbookAfterWrite(FeatureQuery query) =>
      bridgeLoadLibbookFeature(
        _context,
        FeatureId.libbook,
        query,
        bridgeDateOnly(query.date ?? DateTime.now()),
        useCache: false,
      );

  @override
  Future<FeatureResult> readCgyyAfterWrite(FeatureQuery query) =>
      bridgeLoadCgyyFeature(
        _context,
        FeatureId.cgyy,
        query,
        bridgeDateOnly(query.date ?? DateTime.now()),
        useCache: false,
      );

  @override
  Future<FeatureResult> readBykcAfterWrite(FeatureQuery query) =>
      bridgeLoadBykcFeature(_context, FeatureId.bykc, query, useCache: false);

  @override
  Future<FeatureResult> readSigninAfterWrite() =>
      bridgeLoadSigninHome(_context, const FeatureQuery(), useCache: false);

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(FeatureId feature) =>
      bridgeRecoverRequiredSession(_context, feature);
  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) => bridgeLoginRequiredRoute(_context, route, input);
  @override
  Future<LoginVerificationState> beginInteractiveLogin(LoginInput input) =>
      bridgeBeginInteractiveLogin(_context, input);
  @override
  Future<LoginVerificationState> submitInteractiveLogin(
    LoginInput input,
    Map<ConnectionMode, String> answers,
  ) => bridgeSubmitInteractiveLogin(_context, input, answers);
  @override
  Future<LoginVerificationState> refreshInteractiveCaptcha(
    ConnectionMode route,
  ) => bridgeRefreshInteractiveCaptcha(_context, route);
  @override
  Future<InteractiveLoginCompletion> continueInteractiveLogin(
    ConnectionMode route, {
    bool pinRoute = false,
  }) => bridgeContinueInteractiveLogin(_context, route, pinRoute: pinRoute);
  @override
  void discardInteractiveCaptcha(ConnectionMode route) =>
      bridgeDiscardInteractiveCaptcha(_context, route);
  @override
  void cancelInteractiveLogin() => bridgeCancelInteractiveLogin(_context);

  @override
  Future<AuthStatus> authStatus() => bridgeAuthStatus(_context);

  @override
  Future<UserSummary?> userInfo() => bridgeUserInfo(_context);
  @override
  Future<OfflineProfileRead> readCachedProfile(RoutePolicy policy) =>
      bridgeWithOfflineRead(
        _context,
        () => bridgeReadCachedProfile(_context, policy),
      );
  @override
  Future<ProfileRefresh> refreshProfile({required LocalAccount account}) =>
      bridgeWithOfflineRead(
        _context,
        () => bridgeRefreshProfile(_context, account),
      );

  @override
  Future<void> prepareLogin(RoutePolicy policy) =>
      bridgePrepareLogin(_context, policy, setDefaultRoutePolicy);

  Future<BackendRouteSettings> setDefaultRoutePolicy(RoutePolicy policy) =>
      bridgeSetDefaultRoutePolicy(_context, policy);

  @override
  Future<BackendRouteSettings> routeSettings() => bridgeRouteSettings(_context);

  @override
  Future<void> login(LoginInput input) => bridgeLogin(_context, input);

  @override
  Future<void> logout() => bridgeLogout(_context);

  @override
  Future<ScheduleImportTask> beginScheduleImport(String term) =>
      bridgeWithOfflineRead(
        _context,
        () => bridgeBeginScheduleImport(_context, term),
      );

  @override
  Future<FeatureReadTask?> beginAccountFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
    LocalAccount account,
  ) => bridgeWithOfflineRead(
    _context,
    () => bridgeBeginProgressiveRead(
      _context,
      feature,
      query,
      expectedAccount: account,
    ),
  );

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) => bridgeWithOfflineRead(
    _context,
    () => bridgeBeginProgressiveRead(_context, feature, query),
  );

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) => bridgeWithOfflineRead(
    _context,
    () => bridgeLoadFeatureQuery(
      _context,
      feature,
      const FeatureQuery(),
      loadYgdkRecords: false,
    ),
  );

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) => bridgeWithOfflineRead(
    _context,
    () => bridgeLoadFeatureQuery(_context, feature, query),
  );

  @override
  Future<FeatureResult> loadCgyyOrdersOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) => bridgeLoadCgyyOrdersOnRoute(
    _context,
    route: route,
    page: page,
    size: size,
  );

  @override
  Future<FeatureResult> loadCgyyOrderDetailOnRoute({
    required ConnectionMode route,
    required int orderId,
  }) => bridgeLoadCgyyOrderDetailOnRoute(
    _context,
    route: route,
    orderId: orderId,
  );

  @override
  Future<FeatureResult> loadYgdkOverviewOnRoute({
    required ConnectionMode route,
  }) => bridgeLoadYgdkOverviewOnRoute(_context, route: route);

  @override
  Future<FeatureResult> loadYgdkRecordsOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) => bridgeLoadYgdkRecordsOnRoute(
    _context,
    route: route,
    page: page,
    size: size,
  );

  @override
  Future<FeatureResult> loadEvaluationOnRoute({
    required ConnectionMode route,
  }) => bridgeLoadEvaluationOnRoute(_context, route: route);

  @override
  Future<void> dispose() => bridgeDispose(_context);

  @override
  Future<GradeScoreBaseline?> updateGradeScoreBaseline({
    required String accountId,
    required ConnectionMode route,
    required GradeScoreBaseline latest,
    GradeScoreBaseline? legacy,
  }) => bridgeUpdateGradeScoreBaseline(
    _context,
    accountId,
    route,
    latest,
    legacy,
  );

  @override
  Future<List<WriteReadbackHint>> readWriteReadbackHints({
    required String accountId,
  }) => bridgeReadWriteReadbackHints(_context, accountId);
  @override
  Future<void> dismissWriteReadbackHint(
    String id, {
    required String accountId,
  }) => bridgeDismissWriteReadbackHint(_context, accountId, id);

  @override
  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) async =>
      bridgePrepareBykcSelectCourse(_context, courseId: courseId);

  @override
  Future<WriteIntent> prepareBykcDeselectCourse({required int courseId}) =>
      bridgePrepareBykcDeselectCourse(_context, courseId: courseId);

  @override
  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) => bridgePrepareBykcSignCourse(
    _context,
    courseId: courseId,
    lat: lat,
    lng: lng,
    signType: signType,
  );

  @override
  Future<WriteIntent> prepareSigninPerform({required String courseId}) =>
      bridgePrepareSigninPerform(_context, courseId: courseId);

  @override
  Future<WriteIntent> prepareLibbookReserve({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  }) => bridgePrepareLibbookReserve(
    _context,
    areaId: areaId,
    seatId: seatId,
    day: day,
    segment: segment,
    startTime: startTime,
    endTime: endTime,
  );

  @override
  Future<WriteIntent> prepareLibbookCancelBooking({
    required String id,
    required int page,
    required int limit,
  }) => bridgePrepareLibbookCancelBooking(
    _context,
    id: id,
    page: page,
    limit: limit,
  );

  /// 准备阳光打卡。照片字节只在本次调用构造 typed DTO，不写入配置或日志。
  @override
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input) =>
      bridgePrepareYgdkSubmit(_context, input);

  /// 准备研讨室预约；selection 只包含经过 UI 选择的 ID，不接受 raw JSON。
  @override
  Future<WriteIntent> prepareCgyySubmitReservation(CgyySubmitInput input) =>
      bridgePrepareCgyySubmitReservation(_context, input);

  @override
  Future<WriteIntent> prepareCgyyCancelOrder({required int id}) =>
      bridgePrepareCgyyCancelOrder(_context, id: id);

  /// 评教只回传 Core 签发的稳定目标，并在 commit 后按原路线读取核对。
  @override
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationSubmitTarget> targets,
  ) => bridgePrepareEvaluationSubmitCourses(_context, targets);

  @override
  Future<WriteCommitResult> commitWriteWithCache(
    String intentId, {
    required String accountId,
  }) => bridgeCommitWrite(_context, intentId, cacheAccountId: accountId);

  @override
  Future<WriteCommitResult> commitWrite(String intentId) =>
      bridgeCommitWrite(_context, intentId);

  @override
  Future<void> discardWriteIntent(String intentId) =>
      bridgeDiscardWriteIntent(_context, intentId);
}

void _disposeIncompatibleBridgeClient(BridgeClient client) {
  try {
    unawaited(client.dispose().catchError((Object _) {}));
  } on Object {
    // 合同已不兼容，释放失败也不能继续启动该 backend。
  }
}

/// 创建生产后端；任何初始化失败都保持明确的不可用状态，不回退到 Demo。
Future<UbaaBackend> createProductionBackend() async {
  final String directory;
  try {
    directory = defaultConfigDirectory();
  } on Object {
    return const UnavailableBackend(
      failure: InitializationFailure.configuration,
    );
  }
  try {
    return await BridgeBackend.open(directory);
  } on BridgeInitializationError catch (error) {
    return UnavailableBackend(
      failure: switch (error.failure) {
        BridgeInitializationFailure.configuration =>
          InitializationFailure.configuration,
        BridgeInitializationFailure.session => InitializationFailure.session,
        BridgeInitializationFailure.resourceBusy =>
          InitializationFailure.resourceBusy,
        BridgeInitializationFailure.componentUnavailable =>
          InitializationFailure.componentUnavailable,
      },
    );
  } on InitializationException catch (error) {
    return UnavailableBackend(failure: error.failure);
  } on Object {
    return const UnavailableBackend();
  }
}

import 'dart:async';
import 'agenda/backend.dart';
import 'app_service.dart';
import '../contracts/app_service.dart';
import 'ihome/service.dart';
import 'finance/service.dart';
import 'campus/service.dart';
import 'bhpan/service.dart';
import 'cloud_print.dart';
import 'write/pinned_readback.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../../runtime.dart'
    show ControlledRequiredTargetSessionBackend, RequiredRecoveryOperation;
import 'auth/required_session.dart';
import 'auth/network.dart';
import 'auth/shared_logout.dart';
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
        bridgeResumeRequiredCaptcha,
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
import 'support/mapping.dart' show bridgeDateOnly, bridgeMapError;
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

const _supportedBridgeContractVersion = 67;
const _previousBridgeContractVersion = 54;

/// 基于 FRB opaque client 的生产后端。
///
/// 该适配器只负责把 bridge 的 typed 结果投影到应用层；请求 URL、Cookie、
/// Session 和路线选择仍由 Rust Core 管理。测试可以显式注入测试支持包中的脱敏后端，
/// 生产宿主不得把 Demo 作为默认实现。
class BridgeBackend
    implements
        UbaaBackend,
        AgendaProvider,
        HomeTodoBackend,
        IhomeBackend,
        FinanceBackend,
        CampusAccountBackend,
        BhpanProvider,
        CloudPrintProvider,
        PinnedWriteReadbackBackend,
        InteractiveLoginBackend,
        ManualCaptchaBackend,
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
        RoutePolicyBackend,
        NetworkChangeBackend,
        ControlledRequiredTargetSessionBackend,
        HomeRecoveryBatchBackend,
        OfflineCacheBackend,
        ProfileCacheBackend,
        CacheManagementBackend,
        CacheRecoveryBackend,
        CacheWriteBackend,
        WriteReadbackBackend,
        GradeScoreBaselineBackend,
        OfflineQueryBackend,
        ProgressiveReadBackend,
        ConcurrentReadBackend,
        AccountScopedProgressiveReadBackend,
        ScheduleImportBackend,
        BackendLifecycle,
        SharedAccountBackend,
        SharedAccountLogoutBackend,
        AppBootstrapBackend,
        ConfirmedAppServiceAccountBackend {
  BridgeBackend(
    BridgeClient client, {
    String? configDirectory,
    BridgeAppService? appService,
  }) : _appService = appService,
       _context = BridgeContext(client, configDirectory: configDirectory) {
    final contractVersion = client.contractVersion();
    if (contractVersion != _supportedBridgeContractVersion &&
        contractVersion != _previousBridgeContractVersion) {
      _appService?.dispose();
      _disposeIncompatibleBridgeClient(client);
      throw const InitializationException(
        InitializationFailure.bridgeIncompatible,
      );
    }
  }

  @override
  NetworkChangeOperation beginNetworkChange({
    required bool online,
    required Duration budget,
  }) {
    try {
      return BridgeNetworkOperation(
        client.beginNetworkChange(
          online: online,
          timeoutMillis: budget.inMilliseconds,
        ),
      );
    } on BridgeError catch (error) {
      throw bridgeMapError(error);
    }
  }

  @override
  void cancelNetworkReads() => client.cancelNetworkReads();

  @override
  Future<CgyyLockDisplaySession> openLockDisplay() async {
    try {
      return BridgeLockDisplaySession(
        client,
        await client.openCgyyLockDisplay(),
      );
    } on BridgeError catch (error) {
      throw bridgeMapError(error);
    }
  }

  @override
  Future<int> beginHomeRecoveryBatch() => client.contractVersion() < 55
      ? Future.value(0)
      : client.beginReadRecoveryBatch();
  @override
  Future<void> endHomeRecoveryBatch(int batch) =>
      batch == 0 ? Future.value() : client.endReadRecoveryBatch(batch: batch);
  @override
  Future<void> invalidateHomeRecoveryBatch() => client.contractVersion() < 55
      ? Future.value()
      : client.invalidateReadRecoveryBatch();

  /// 从平台已经解析好的应用私有目录打开 Core。
  static Future<BridgeBackend> open(
    String configDirectory, {
    BridgeAppService? appService,
  }) async {
    final BridgeClient client;
    try {
      client = appService == null
          ? await BridgeClient.open(configDir: configDirectory)
          : await BridgeClient.openWithAppService(
              configDir: configDirectory,
              appService: appService,
            );
    } on Object {
      appService?.dispose();
      rethrow;
    }
    return BridgeBackend(
      client,
      configDirectory: configDirectory,
      appService: appService,
    );
  }

  final BridgeAppService? _appService;

  Future<AppServiceView> _appServiceView(
    Future<BridgeAppServiceState> Function(BridgeAppService) read,
  ) async {
    final service = _appService;
    return service == null || _context.closed
        ? AppServiceView.unavailable(bundledPrivacyPolicy.version)
        : bridgeAppServiceView(await read(service));
  }

  @override
  Future<AppServiceView> appServiceState() =>
      _appServiceView((service) => service.state());
  @override
  Future<AppServiceView> agreeAppService() =>
      _appServiceView((service) => service.agree());
  @override
  Future<AppServiceView> enterBasicAppService() =>
      _appServiceView((service) => service.enterBasic());
  @override
  Future<AppServiceView> setAppServiceTelemetry(bool enabled) =>
      _appServiceView((service) => service.setTelemetry(enabled: enabled));

  @override
  Future<void> refreshAppBootstrap({required bool force}) async {
    if (!_context.closed) await _appService?.refreshBootstrap(force: force);
  }

  @override
  Future<AppServiceView> markAppAnnouncementRead(String id) =>
      _appServiceView((service) => service.markAnnouncementRead(id: id));

  @override
  Future<AppServiceView> dismissAppUpdateAvailable(String latestVersion) =>
      _appServiceView(
        (service) =>
            service.dismissUpdateAvailable(latestVersion: latestVersion),
      );

  @override
  Future<AppServiceEraseOutcome> eraseAppService() async {
    final service = _appService;
    if (service == null || _context.closed)
      return AppServiceEraseOutcome.unavailable;
    return bridgeAppServiceErase(await service.erase());
  }

  @override
  Future<void> uploadAppService({required bool force}) async {
    if (!_context.closed) await _appService?.upload(force: force);
  }

  @override
  Future<void> recordAppService(TelemetryRecord record) async {
    if (_appService case final service? when !_context.closed) {
      await bridgeRecordAppService(service, record);
    }
  }

  @override
  void confirmAppServiceAccount() {
    final scope = _context.nativeAccount;
    final binding = _context.sharedAccount;
    if (_context.closed || scope == null || binding == null) return;
    try {
      _appService?.bindAccount(
        scope: scope,
        expectedUsername: binding.account.username,
      );
    } on Object {
      // 统计账号绑定失败不改变登录、恢复和本机缓存的业务结果。
    }
  }

  @override
  void clearAppServiceAccount() {
    if (_context.closed) return;
    try {
      _appService?.clearAccount();
    } on Object {
      // Core 在入队时仍按共享代次校验账号。
    }
  }

  @override
  Future<void> bindSharedAccount(SharedAccountBinding binding) async {
    void check() {
      if (_context.closed)
        throw const BackendException(
          UbaaErrorCode.operationConflict,
          clientDisposed: true,
        );
    }

    check();
    if (binding.isRevocation)
      throw const BackendException(UbaaErrorCode.invalidInput);
    await binding.validate();
    check();
    final reopened = agenda.accountId != null;
    await agenda.close();
    check();
    _context.cache.generation++;
    await _context.cache.tail;
    check();
    final native = await BridgeSharedAccount.capture(
      directory: binding.directory,
      generation: BigInt.from(binding.generation),
    );
    var adopted = false;
    try {
      check();
      await client.bindSharedAccount(scope: native);
      check();
      await binding.validate();
      check();
      final oldCache = _context.cache.handle;
      BridgeOfflineCache? nextCache;
      if (oldCache != null &&
          _context.cache.account?.id == binding.account.id) {
        nextCache = await oldCache.withSharedAccount(scope: native);
        if (_context.closed) {
          nextCache.dispose();
          check();
        }
      } else if (oldCache != null) {
        await oldCache.close();
        check();
        _context.cache.account = null;
        _context.cache.targetAccountId = null;
      }
      final oldNative = _context.nativeAccount;
      _context.sharedAccount = binding;
      _context.nativeAccount = native;
      _context.cache.handle = nextCache;
      adopted = true;
      oldCache?.dispose();
      oldNative?.dispose();
      if (reopened) await agenda.openAccount(binding.account.id);
    } finally {
      if (!adopted) native.dispose();
    }
  }

  @override
  Future<void> logoutSharedAccount(
    SharedAccountBinding revoked, {
    required bool clearCache,
  }) async {
    clearAppServiceAccount();
    await agenda.close();
    return bridgeSharedLogout(_context, revoked, clearCache: clearCache);
  }

  final BridgeContext _context;
  @override
  Future<HomeTodoProjection> projectHomeTodos(HomeTodoRequest request) =>
      bridgeWithOfflineRead(
        _context,
        () => _homeAgenda.projectHomeTodos(request),
      );
  late final BridgeAgendaBackend _homeAgenda = BridgeAgendaBackend(_context);
  @override
  late final AgendaService agenda = AgendaService(_homeAgenda);
  @override
  late final FinanceService finance = BridgeFinanceService(
    _context,
    () => BridgeRequiredSessionBackend(
      _context.client,
    ).recoverTargetSession(RecoveryTarget.finance),
  );

  @override
  late final IhomeService ihome = BridgeIhomeService(_context.client);
  @override
  late final BhpanService bhpan = BridgeBhpanService(_context);

  @override
  late final CloudPrintService cloudPrint = BridgeCloudPrintService(_context);
  @override
  late final CampusAccountService campusAccount = BridgeCampusAccountService(
    _context,
  );
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
      if (_context.sharedAccount == null)
        await _context.cache.handle?.deactivate();
      _context.cache.targetAccountId = null;
    });
  }

  @override
  Future<void> clearOfflineAccount({required String accountId}) {
    _context.cache.generation++;
    _context.cache.targetAccountId = null;
    return bridgeOfflineSerial(_context, () async {
      final handle = _context.cache.handle;
      if (handle == null || _context.cache.account?.id != accountId) {
        throw const BackendException(
          UbaaErrorCode.internalError,
          cacheFailure: CacheMaintenanceFailure.unavailable,
        );
      }
      await handle.clear();
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
  RequiredRecoveryOperation startTargetRecovery(
    RecoveryTarget target,
    Duration limit,
  ) => BridgeRequiredSessionBackend(
    _context.client,
  ).startTargetRecovery(target, limit);
  @override
  Future<RecoveredRouteSession> recoverTargetSession(RecoveryTarget target) =>
      BridgeRequiredSessionBackend(
        _context.client,
      ).recoverTargetSession(target);

  @override
  RequiredRecoveryOperation startRequiredRecovery(
    FeatureId feature,
    Duration limit,
  ) => BridgeRequiredSessionBackend(
    _context.client,
  ).startRequiredRecovery(feature, limit);
  @override
  RequiredRecoveryOperation startRequiredLogin(
    ConnectionMode route,
    LoginInput input,
    Duration limit,
  ) => BridgeRequiredSessionBackend(
    _context.client,
  ).startRequiredLogin(route, input, limit);
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
  Future<LoginVerificationState> resumeRequiredCaptcha(
    LoginInput input,
    ConnectionMode route,
  ) => bridgeResumeRequiredCaptcha(_context, input, route);
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
  Future<void> logout() {
    clearAppServiceAccount();
    return bridgeLogout(_context);
  }

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

  Future<void>? _closing;
  @override
  Future<void> dispose() {
    if (_closing != null) return _closing!;
    _context.closed = true;
    _appService?.dispose();
    _context.cache.generation++;
    _context.cache.targetAccountId = null;
    final agendaClosed = agenda.dispose();
    final clientClosed = bridgeDispose(_context);
    final cacheClosed = bridgeOfflineSerial(_context, () async {
      await _context.cache.handle?.close();
      _context.cache.handle?.dispose();
      _context.cache.handle = null;
      _context.cache.account = null;
      _context.nativeAccount?.dispose();
      _context.nativeAccount = null;
    });
    return _closing = Future.wait([
      agendaClosed,
      clientClosed,
      cacheClosed,
    ]).then((_) {});
  }

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
Future<UbaaBackend> createProductionBackend({
  Future<BridgeAppService?> Function(String directory)? openAppService,
}) async {
  final String directory;
  try {
    directory = defaultConfigDirectory();
  } on Object {
    return const UnavailableBackend(
      failure: InitializationFailure.configuration,
    );
  }
  BridgeAppService? appService;
  try {
    appService = await openAppService?.call(directory);
  } on Object {
    // 可选统计初始化失败时仍然打开学校业务后端。
  }
  try {
    return await BridgeBackend.open(directory, appService: appService);
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

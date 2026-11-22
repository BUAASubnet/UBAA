import 'dart:async';

import 'agenda/backend.dart';
import 'app_service.dart';
import '../contracts/app_service.dart';
import 'ihome/service.dart';
import 'health_cloud.dart';
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
import 'features/signin/reader.dart'
    show bridgeFetchSigninQr, bridgeLoadSigninHome;
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

part 'bridge_backend_app_service.dart';
part 'bridge_backend_auth.dart';
part 'bridge_backend_read.dart';
part 'bridge_backend_write.dart';

const _supportedBridgeContractVersion = 78;
const _previousBridgeContractVersion = 54;

/// 基于 FRB opaque client 的生产后端。
///
/// 该适配器只负责把 bridge 的 typed 结果投影到应用层；请求 URL、Cookie、
/// Session 和路线选择仍由 Rust Core 管理。测试可以显式注入测试支持包中的脱敏后端，
/// 生产宿主不得把 Demo 作为默认实现。
class BridgeBackend
    with
        BridgeBackendAppService,
        BridgeBackendAuth,
        BridgeBackendRead,
        BridgeBackendWrite
    implements
        UbaaBackend,
        RawDiagnosticsBackend,
        AgendaProvider,
        HomeTodoBackend,
        IhomeBackend,
        HealthCloudBackend,
        FinanceBackend,
        CampusAccountBackend,
        BhpanProvider,
        CloudPrintProvider,
        PinnedWriteReadbackBackend,
        InteractiveLoginBackend,
        ManualCaptchaBackend,
        CgyyLockDisplayBackend,
        FeatureQueryBackend,
        SigninQrBackend,
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
        ConfirmedAppServiceAccountBackend,
        HostPrivacyAppServiceBackend,
        SavedSessionBackend {
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

  @override
  final BridgeAppService? _appService;

  @override
  final BridgeContext _context;
  @override
  BridgeClient get client => _context.client;
  String? get configDirectory => _context.configDirectory;

  @override
  Future<void>? _closing;
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

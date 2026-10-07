import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/schedule_import.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/lifecycle.dart';
import 'package:ubaa_app/src/contracts/profile.dart';
import 'package:ubaa_app/src/contracts/cache_management.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import 'package:ubaa_app/src/contracts/write.dart';
import 'package:ubaa_app/src/write/coordinator.dart';
import 'models.dart'
    show
        AcademicWeeksCache,
        BusinessRetry,
        CgyyPurposeCache,
        GradesReadCache,
        GuardedLockDisplaySession,
        HomeSupplementCache,
        ProfileRequest,
        ProgressiveScope,
        RecoveryRequest,
        RecoveryRetry,
        ScheduleImportScope,
        WriteReadbackRead,
        WriteRefreshRequest;
import 'operations.dart' show ControllerOperations;
import 'types.dart' show AppPhase, LoginFormState, SessionRecoveryStatus;

abstract class ControllerState extends ControllerOperations {
  ControllerState({
    required UbaaBackend backend,
    BackendFactory? backendFactory,
    CredentialVault? credentialVault,
    LocalAccountStore? localAccountStore,
    TelemetryClient? telemetry,
    LocalDiagnostics? diagnostics,
    void Function(ReadSchedulerTrace trace)? onReadSchedulerTrace,
  }) : internalBackend = backend,
       internalBackendFactory = backendFactory,
       internalCredentialVault = credentialVault ?? const NoopCredentialVault(),
       internalLocalAccountStore = localAccountStore,
       internalTelemetry = telemetry ?? const NoopTelemetryClient(),
       internalDiagnostics = diagnostics ?? LocalDiagnostics(),
       internalTelemetryEnabled =
           (telemetry ?? const NoopTelemetryClient()).enabled,
       internalSnapshots = {
         for (final feature in FeatureId.values)
           feature: FeatureSnapshot(feature: feature),
       } {
    internalWriteCoordinator = internalCreateWriteCoordinator(backend);
    internalReadScheduler = ReadScheduler(
      canRun: internalCanRunScheduledRead,
      onTrace: onReadSchedulerTrace,
    );
    internalWriteCoordinator.addListener(internalNotify);
  }

  @internal
  UbaaBackend internalBackend;

  @internal
  final BackendFactory? internalBackendFactory;

  @internal
  final CredentialVault internalCredentialVault;

  @internal
  final LocalAccountStore? internalLocalAccountStore;

  @internal
  LocalAccount? internalLocalAccount;

  @internal
  bool internalIsSigningOut = false;

  @internal
  bool internalCredentialRestoreAllowed = true;

  @internal
  bool internalManualAuthenticationRequired = false;

  @internal
  int internalLoginFormRevision = 0;

  @internal
  int internalLoginCredentialRevision = 0;

  @internal
  int internalInteractiveGeneration = 0;

  @internal
  bool internalInteractiveInPlace = false;

  @internal
  bool internalInteractiveEngaged = false;

  @internal
  LoginVerificationState? internalLoginVerification;

  @internal
  final Map<ConnectionMode, Timer> internalCaptchaTimers = {};

  @internal
  int internalRoutePolicyGeneration = 0;

  @internal
  bool internalRoutePolicyInFlight = false;

  @internal
  Completer<void>? internalBackendRebuildCompletion;

  @internal
  Future<void>? internalCredentialMutation;

  @internal
  bool internalClearingBusinessCache = false;

  @internal
  int internalBusinessCacheEpoch = 0;

  bool get isClearingBusinessCache => internalClearingBusinessCache;

  bool get canClearBusinessCache =>
      cacheAccountId != null &&
      !internalDisposed &&
      !internalClearingBusinessCache &&
      !internalInteractiveEngaged &&
      !isLoggingIn &&
      !internalRebuildingBackend &&
      internalWriteTransitions == 0 &&
      internalActiveRecovery == null &&
      !internalWriteCoordinator.hasPendingOperation;

  int get businessCacheEpoch => internalBusinessCacheEpoch;

  String? get cacheAccountId =>
      internalPhase == AppPhase.home &&
          !internalIsSigningOut &&
          internalBackend is CacheManagementBackend
      ? internalLocalAccount?.id
      : null;

  @internal
  bool internalAutomaticCredentialBlocked = false;

  @internal
  GuardedLockDisplaySession? internalLockDisplay;

  @internal
  int internalLockDisplayGeneration = 0;

  @internal
  bool internalAppForeground = true;

  @internal
  final internalRecoveryRetries = <FeatureId, RecoveryRetry>{};

  @internal
  final internalBusinessRetries = <(FeatureId, bool), BusinessRetry>{};

  @internal
  Timer? internalNetworkWakeCooldown;

  @internal
  final internalQueuedRecoveries = <FeatureId, RecoveryRequest>{};

  @internal
  RecoveryRequest? internalActiveRecovery;

  @internal
  ConnectionMode? internalRecoveredRoute;

  @internal
  final internalFeatureRecoveryStates = <FeatureId, SessionRecoveryStatus>{};

  @internal
  final internalFeatureRecoveryErrors = <FeatureId, UiError>{};

  @internal
  int internalReadRequestRevision = 0;

  ConnectionMode? get recoveredRoute => internalRecoveredRoute;

  @internal
  bool internalDeferredRecoveryScheduled = false;

  @internal
  int? internalPendingHomeRecoveryEpoch;

  @internal
  Future<void> internalOfflineOpenFuture = Future<void>.value();

  @internal
  int internalOfflineAccountEpoch = 0;

  @internal
  UiError? internalLocalCacheError;

  UiError? get localCacheError => internalLocalCacheError;

  @internal
  List<WriteReadbackHint> internalWriteReadbacks = const [];

  List<WriteReadbackHint> get writeReadbacks =>
      List.unmodifiable(internalWriteReadbacks);

  @internal
  UiError? internalWriteReadbackError;

  UiError? get writeReadbackError => internalWriteReadbackError;

  @internal
  int internalWriteReadbackRevision = 0, internalWriteReadbackLoadedEpoch = -1;

  @internal
  WriteReadbackRead? internalWriteReadbackRead;

  @internal
  bool internalUsesLocalRecovery = false;

  @internal
  SessionRecoveryStatus internalSessionRecoveryStatus =
      SessionRecoveryStatus.idle;

  @internal
  Future<void>? internalSessionRecoveryFuture;

  @internal
  bool internalHomeFrameReported = false;

  @internal
  bool internalInPlaceLogin = false;

  bool get isLoggingIn =>
      internalInPlaceLogin || internalPhase == AppPhase.loggingIn;

  SessionRecoveryStatus get sessionRecoveryStatus =>
      internalSessionRecoveryStatus;

  bool get usesLocalRecovery => internalUsesLocalRecovery;

  @internal
  final TelemetryClient internalTelemetry;

  @internal
  final LocalDiagnostics internalDiagnostics;

  @internal
  final Map<FeatureId, FeatureSnapshot> internalSnapshots;

  @internal
  late WriteCoordinator internalWriteCoordinator;

  @internal
  late final ReadScheduler internalReadScheduler;

  @internal
  final internalReadScopes = <ProgressiveScope>{};

  @internal
  final internalScheduleImportScopes = <String, ScheduleImportScope>{};

  @internal
  final internalScheduleImports = <String, ScheduleImportState>{};

  @internal
  int internalScheduleImportEpoch = -1;

  Map<String, ScheduleImportState> get scheduleImports =>
      Map.unmodifiable(internalScheduleImports);

  bool get canSaveScheduleSemester =>
      !internalDisposed &&
      !internalIsSigningOut &&
      !internalClearingBusinessCache &&
      internalPhase == AppPhase.home &&
      internalLocalAccount != null &&
      internalBackend is ScheduleImportBackend;

  @internal
  int internalWriteTransitions = 0;

  @internal
  final internalWriteRefreshes = <FeatureId, WriteRefreshRequest>{};

  @internal
  bool internalWriteRefreshScheduled = false;

  @internal
  AppPhase internalPhase = AppPhase.splash;

  @internal
  LoginFormState internalLoginForm = const LoginFormState();

  @internal
  UserSummary? internalUser;

  @internal
  UserSummary? internalProfileDisplay;

  @internal
  int internalProfileDisplayEpoch = -1,
      internalProfileRefreshedEpoch = -1,
      internalProfileFailureEpoch = -1;

  @internal
  DateTime? internalProfileRefreshedAt;

  @internal
  RoutePolicy? internalProfileRefreshedPolicy;

  @internal
  ProfileRequest? internalProfileRequest;

  @internal
  UiError? internalError;

  @internal
  bool internalDisposed = false;

  @internal
  bool internalInitialized = false;

  @internal
  final Map<FeatureId, int> internalFeatureRefreshGenerations =
      <FeatureId, int>{for (final feature in FeatureId.values) feature: 0};

  @internal
  final internalHomeDefaults = <FeatureId, FeatureSnapshot>{
    for (final feature in FeatureId.values)
      feature: FeatureSnapshot(feature: feature),
  };

  @internal
  HomeSupplementCache? internalHomeSupplementCache;

  @internal
  GradesReadCache? internalGradesReadCache;

  @internal
  AcademicWeeksCache? internalAcademicWeeksCache;

  @internal
  CgyyPurposeCache? internalCgyyPurposeCache;

  @internal
  FeatureResult? internalAcademicTermsResult;

  @internal
  Future<FeatureResult>? internalAcademicTermsPending;

  @internal
  ReadDemand? internalAcademicTermsDemand;

  @internal
  UbaaBackend? internalAcademicTermsBackend;

  @internal
  int internalAcademicTermsEpoch = -1;

  @internal
  int internalAcademicTermsLifecycle = -1;

  @internal
  int internalAcademicTermsSerial = 0;

  @internal
  int internalLifecycleEpoch = 0;

  @internal
  int internalReadCacheEpoch = 0;

  /// UI 返回帧缓存的失效代次；不改变当前可见旧快照的 stale 语义。
  int get readCacheEpoch => internalReadCacheEpoch;

  @internal
  int internalYgdkGeneration = 0;

  @internal
  bool internalTelemetryEnabled;

  @internal
  YgdkReadbackState internalYgdkReadbackState = const YgdkReadbackState.empty();

  @internal
  List<ConnectionMode> internalActiveRoutes = const <ConnectionMode>[];

  @internal
  bool internalRebuildingBackend = false;

  @internal
  /// Expando 按实例身份关联释放 Future，且不会因去重表阻止已释放
  /// backend 被回收。
  final Expando<Future<void>> internalBackendDisposals =
      Expando<Future<void>>();

  AppPhase get phase => internalPhase;

  LoginFormState get loginForm => internalLoginForm;

  LoginVerificationState? get loginVerification => internalLoginVerification;

  UserSummary? get user => internalUser;

  /// 宿主仅用于展示；认证、提醒归属和写入仍使用user。
  UserSummary? get displayUser {
    if (internalIsSigningOut) return null;
    if (internalPhase != AppPhase.home || internalUser == null)
      return internalUser;
    final account = internalLocalAccount;
    if (account == null) return internalUser;
    if (internalProfileDisplay?.accountScope == account.id)
      return internalProfileDisplay;
    return profileDisplay(internalUser!, null, null, accountScope: account.id);
  }

  UiError? get error => internalError;

  bool get telemetryEnabled => internalTelemetryEnabled;

  /// 实际客户端能力与本地开关分离；关闭本地开关不销毁已配置的客户端。
  bool get telemetryAvailable => internalTelemetry.enabled;

  bool get credentialPersistenceAvailable =>
      internalCredentialVault.isAvailable;

  List<ConnectionMode> get activeRoutes =>
      List<ConnectionMode>.unmodifiable(internalActiveRoutes);

  bool get isRebuildingBackend => internalRebuildingBackend;

  Map<FeatureId, FeatureSnapshot> get snapshots =>
      Map<FeatureId, FeatureSnapshot>.unmodifiable(internalSnapshots);

  YgdkReadbackState get ygdkReadbackState => internalYgdkReadbackState;

  WriteCoordinator get writeCoordinator => internalWriteCoordinator;

  LocalDiagnostics get diagnostics => internalDiagnostics;

  /// backend 必须同时提供 typed 写入与原路线回读，宿主才可暴露
  /// 阳光打卡提交入口。平台照片能力仍由宿主另行检查。
  bool get hasYgdkSubmissionBackendCapabilities =>
      internalBackend is YgdkWriteBackend &&
      internalBackend is YgdkSubmissionReadbackBackend;

  /// backend 必须同时提供 typed 写入与调用方固定路线回读，
  /// 宿主才能暴露评教提交入口。
  bool get hasEvaluationSubmissionBackendCapabilities =>
      internalBackend is EvaluationWriteBackend &&
      internalBackend is EvaluationSubmissionReadbackBackend;

  /// 首页默认来源与领域当前查询隔离；不授予额外写资格。
  Map<FeatureId, FeatureSnapshot> get homeSnapshots =>
      Map.unmodifiable(internalHomeDefaults);

  LocalDataOwnerScope get internalLocalDataOwnerScope;
}

/// 宿主本地偏好的拥有者及其生命期，不包含凭据或写资格。
final class LocalDataOwnerScope {
  LocalDataOwnerScope.capture(this._controller)
    : _epoch = _controller.internalLifecycleEpoch,
      accountKey = _controller.internalUser?.schoolId?.trim().isNotEmpty == true
          ? _controller.internalUser!.schoolId!
          : (_controller.internalUser?.username ?? ''),
      identities = Set.unmodifiable(
        {
          _controller.internalLocalAccount?.username,
          _controller.internalUser?.username,
          _controller.internalUser?.schoolId,
        }.whereType<String>().where((key) => key.trim().isNotEmpty),
      );

  final ControllerState _controller;
  final int _epoch;
  final String accountKey;
  final Set<String> identities;

  void checkCurrent() {
    final c = _controller;
    if (c.internalDisposed ||
        c.internalIsSigningOut ||
        c.internalPhase != AppPhase.home ||
        c.internalLifecycleEpoch != _epoch) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
  }
}

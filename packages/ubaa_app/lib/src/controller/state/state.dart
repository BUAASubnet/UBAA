import 'dart:async';
import '../../services/session_recovery.dart';
import '../../contracts/session_recovery.dart';
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
        BusinessRetry,
        GuardedLockDisplaySession,
        ProfileRequest,
        ProgressiveScope,
        RecoveryRequest,
        RecoveryRetry,
        ScheduleImportScope,
        WriteReadbackRead,
        WriteRefreshRequest;
import 'read_scope.dart';
import 'lifecycle_owners.dart';
import 'read_caches.dart';
import 'academic_terms.dart' show CurrentTermsReader;
import 'operations.dart' show ControllerOperations;
import 'types.dart' show AppPhase, LoginFormState, SessionRecoveryStatus;

final _schoolPromptZone = Object();

abstract class ControllerState extends ControllerOperations {
  ControllerState({
    required UbaaBackend backend,
    BackendFactory? backendFactory,
    CredentialVault? credentialVault,
    LocalAccountStore? localAccountStore,
    TelemetryClient? telemetry,
    LocalDiagnostics? diagnostics,
    void Function(ReadSchedulerTrace trace)? onReadSchedulerTrace,
  }) : internalSessionLifecycle = SessionLifecycleOwner(backend),
       internalBackendFactory = backendFactory,
       internalCredentialVault = credentialVault ?? const NoopCredentialVault(),
       internalLocalAccountStore = localAccountStore,
       internalTelemetry = telemetry ?? const NoopTelemetryClient(),
       internalDiagnostics = diagnostics ?? LocalDiagnostics(),
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
  final SessionLifecycleOwner internalSessionLifecycle;
  @internal
  final CacheLifecycleOwner internalCacheLifecycle = CacheLifecycleOwner();
  @internal
  SessionScope internalCaptureSessionScope() =>
      internalSessionLifecycle.capture();
  @internal
  ReadScope internalCaptureReadScope() =>
      internalCacheLifecycle.captureRead(internalCaptureSessionScope());
  @internal
  OfflineAccountScope internalCaptureOfflineScope(String account) {
    final local = internalLocalAccount;
    return internalCacheLifecycle.captureOffline(
      session: internalCaptureSessionScope(),
      accountId: local?.id,
      opened: internalOfflineOpenFuture,
      accountCurrent: () =>
          internalPhase == AppPhase.home &&
          internalLocalAccount?.id == local?.id &&
          [internalUser?.schoolId, internalUser?.username].contains(account),
    );
  }

  @internal
  UbaaBackend get internalBackend => internalSessionLifecycle.backend;

  @internal
  final BackendFactory? internalBackendFactory;

  @internal
  final internalRequiredRecoveryServices =
      <UbaaBackend, RequiredSessionRecovery>{};

  @internal
  final CredentialVault internalCredentialVault;

  @internal
  final LocalAccountStore? internalLocalAccountStore;

  @internal
  LocalAccount? internalLocalAccount;
  @internal
  LocalAccountSnapshot? internalSharedAccountSnapshot;
  @internal
  RecoveryScope? internalSharedRecoveryScope;

  @internal
  bool get internalIsSigningOut => internalSessionLifecycle.signingOut;

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

  /// 路线切换前已发出的读取不能重新赋予首页签到动作。
  @internal
  int internalRoutePolicyReadRevision = -1;

  @internal
  bool internalRoutePolicyInFlight = false;

  @internal
  Completer<void>? internalBackendRebuildCompletion;

  @internal
  Future<void>? internalCredentialMutation;

  @internal
  bool get internalClearingBusinessCache => internalCacheLifecycle.clearing;

  @internal
  int internalBusinessCacheEpoch = 0;

  @internal
  int internalLocalDataGeneration = 0;

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
  bool internalAutomaticLoginDisabled = false;

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
  Future<int>? internalHomeRecoveryBatch;
  @internal
  Future<void> internalAgendaOpenFuture = Future<void>.value();
  @internal
  int internalAgendaEpoch = 0;
  @internal
  int internalAgendaOpenEpoch = 0;
  @internal
  AgendaFailure? internalAgendaFailure;
  int get agendaProjectionEpoch => internalAgendaEpoch;
  AgendaFailure? get localAgendaFailure => internalAgendaFailure;

  @internal
  ({
    String? accountId,
    int routeGeneration,
    String term,
    ConnectionMode? route,
  })?
  internalAgendaSchoolScope;

  /// 保留当前会话最后确认的学期，普通刷新不改变日程作用域。
  String get currentAgendaTerm {
    final school = internalAgendaSchoolScope;
    if (internalDisposed ||
        internalPhase != AppPhase.home ||
        school == null ||
        school.accountId !=
            (internalLocalAccount?.id ?? internalUser?.username) ||
        school.routeGeneration != internalRoutePolicyGeneration)
      return '';
    return school.term;
  }

  ConnectionMode? get currentAgendaRoute =>
      currentAgendaTerm.isEmpty ? null : internalAgendaSchoolScope?.route;

  AgendaService? get agenda {
    final backend = internalBackend;
    if (internalDisposed ||
        internalIsSigningOut ||
        internalRebuildingBackend ||
        internalPhase != AppPhase.home ||
        internalLocalAccount == null ||
        backend is! AgendaProvider)
      return null;
    final service = (backend as AgendaProvider).agenda;
    return service.accountId == internalLocalAccount!.id ? service : null;
  }

  @internal
  int get internalOfflineAccountEpoch => internalCacheLifecycle.offlineEpoch;

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
  bool get internalDisposed => internalSessionLifecycle.disposed;

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
  final internalReadCaches = ControllerReadCaches();

  @internal
  CurrentTermsReader get internalCurrentTermsReader => internalReadCaches.terms;

  @internal
  int get internalLifecycleEpoch => internalSessionLifecycle.epoch;

  @internal
  int get internalReadCacheEpoch => internalCacheLifecycle.readEpoch;

  /// UI 返回帧缓存的失效代次；不改变当前可见旧快照的 stale 语义。
  int get readCacheEpoch => internalReadCacheEpoch;

  @internal
  int internalYgdkGeneration = 0;

  @internal
  YgdkReadbackState internalYgdkReadbackState = const YgdkReadbackState.empty();

  @internal
  List<ConnectionMode> internalActiveRoutes = const <ConnectionMode>[];

  @internal
  bool get internalRebuildingBackend => internalSessionLifecycle.rebuilding;

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

  @internal
  AppServiceView internalAppServiceView = AppServiceView.unavailable(
    bundledPrivacyPolicy.version,
  );

  final _updatePrompts = StreamController<void>.broadcast();
  Stream<void> get updatePromptRequests => _updatePrompts.stream;

  /// 一个主动操作可能并行读取多个来源；只发送一次提示。
  @internal
  Future<T> internalUserSchoolAction<T>(Future<T> Function() action) {
    Future<T> run() async {
      try {
        final value = await action();
        internalReportSchoolRejection(switch (value) {
          final FeatureResult result => result.error,
          final GradesAggregate result =>
            result.error?.code == UbaaErrorCode.updateRequired
                ? result.error
                : result.terms
                      .map((term) => term.result.error)
                      .where(
                        (error) => error?.code == UbaaErrorCode.updateRequired,
                      )
                      .firstOrNull,
          final GradeTermRead read => read.result.error,
          final WriteCommitResult result
              when result.evaluationResult?.stoppedForUpdate == true =>
            const BackendException(
              UbaaErrorCode.updateRequired,
              retryable: false,
            ),
          _ => null,
        });
        return value;
      } on Object catch (error) {
        internalReportSchoolRejection(error);
        rethrow;
      }
    }

    if (internalSchoolPrompt != null) return run();
    var reported = false;
    void report(Object? error) {
      if (reported || !_updateRejection(error)) return;
      reported = true;
      internalReportUserSchoolRejection(error);
    }

    return runZoned(run, zoneValues: {_schoolPromptZone: report});
  }

  @internal
  T internalAutomaticSchoolAction<T>(T Function() action) =>
      internalSchoolPrompt == null
      ? action()
      : runZoned(action, zoneValues: {_schoolPromptZone: false});

  @internal
  void Function(Object?)? get internalSchoolPrompt {
    final value = Zone.current[_schoolPromptZone];
    return value is void Function(Object?) ? value : null;
  }

  @internal
  void internalReportSchoolRejection(Object? error) =>
      internalSchoolPrompt?.call(error);

  bool _updateRejection(Object? error) => switch (error) {
    final BackendException value => value.code == UbaaErrorCode.updateRequired,
    final UiError value => value.code == UbaaErrorCode.updateRequired,
    _ => false,
  };

  @internal
  void internalReportUserSchoolRejection(Object? error) {
    if (!internalDisposed && _updateRejection(error)) _updatePrompts.add(null);
  }

  @internal
  void internalDisposeUpdatePrompts() => unawaited(_updatePrompts.close());

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
  @internal
  LocalDataOwnerScope.capture(this._controller)
    : _epoch = _controller.internalLocalDataGeneration,
      _accountId = _controller.internalLocalAccount?.id,
      accountKey =
          _controller.internalLocalAccount?.username ??
          (_controller.internalUser?.schoolId?.trim().isNotEmpty == true
              ? _controller.internalUser!.schoolId!
              : (_controller.internalUser?.username ?? '')),
      identities = Set.unmodifiable(
        {
          _controller.internalLocalAccount?.username,
          _controller.internalUser?.username,
          _controller.internalUser?.schoolId,
        }.whereType<String>().where((key) => key.trim().isNotEmpty),
      );

  final ControllerState _controller;
  final int _epoch;
  final String? _accountId;
  final String accountKey;
  final Set<String> identities;

  void checkCurrent() {
    final c = _controller;
    if (c.internalDisposed ||
        c.internalIsSigningOut ||
        c.internalPhase != AppPhase.home ||
        c.internalUser == null ||
        c.internalLocalDataGeneration != _epoch ||
        c.internalLocalAccount?.id != _accountId ||
        (_accountId == null &&
            (c.internalUser?.schoolId?.trim().isNotEmpty == true
                    ? c.internalUser!.schoolId!
                    : c.internalUser?.username) !=
                accountKey)) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
  }
}

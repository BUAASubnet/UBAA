import 'dart:async';
import 'home/presentation.dart';
import 'agenda/lifecycle.dart';
import 'state/types.dart' show AppPhase;
import 'features/ihome/service.dart';
import 'features/finance/service.dart';
import 'features/campus/service.dart';
import 'features/bhpan/service.dart';
import 'features/cloud_print.dart';
import 'error_mapper.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/query.dart' show SigninReadbackBackend;
import 'package:ubaa_app/src/contracts/signin/qr.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/lifecycle.dart';
import 'package:ubaa_app/src/contracts/recovery.dart' show RecoveryTarget;
import 'cache/home.dart' show ControllerOfflineCache;
import 'cache/management.dart' show ControllerCacheManagement;
import 'features/academic/terms.dart' show ControllerAcademicTerms;
import 'features/academic/weeks.dart' show ControllerAcademicWeeks;
import 'features/cgyy/lock_display.dart' show ControllerLockDisplay;
import 'features/cgyy/purposes.dart' show ControllerCgyyPurposes;
import 'features/grades/queries.dart' show ControllerGrades;
import 'features/home/sources.dart' show ControllerHomeSources;
import 'features/profile/profile.dart' show ControllerProfile;
import 'features/refresh.dart' show ControllerRefresh;
import 'features/schedule/import.dart' show ControllerScheduleImport;
import 'features/schedule/widgets.dart' show ControllerScheduleWidgets;
import 'lifecycle/actions.dart' show ControllerLifecycleActions;
import 'lifecycle/app_service.dart' show ControllerAppService;
import 'lifecycle/diagnostics.dart' show ControllerDiagnostics;
import 'reads/actions.dart' show ControllerReadActions;
import 'reads/progressive.dart' show ControllerProgressive;
import 'reads/readback.dart' show ControllerReadbackDispatch;
import 'reads/session.dart' show ControllerScheduledSession;
import 'recovery/backend_rebuild.dart' show ControllerBackendRecovery;
import 'recovery/business_retry.dart' show ControllerBusinessRetry;
import 'recovery/grades.dart' show ControllerOfflineGrades;
import 'recovery/query.dart' show ControllerOfflineQuery;
import 'recovery/read_options.dart' show ControllerLocalReadOptions;
import 'recovery/required.dart' show ControllerRequiredRecovery;
import 'recovery/services.dart' show ControllerServiceRecovery;
import 'recovery/resume.dart' show ControllerDeferredRecovery;
import 'recovery/retry.dart' show ControllerRecoveryRetry;
import 'recovery/startup.dart' show ControllerOfflineStartup;
import 'recovery/network.dart' show ControllerNetworkRecovery;
import 'session/completion.dart' show ControllerAuthenticationCompletion;
import 'session/authentication.dart' show ControllerAuthentication;
import 'session/form_actions.dart' show ControllerFormActions;
import 'session/interactive.dart' show ControllerInteractiveAuthentication;
import 'session/logout.dart' show ControllerLocalData, ControllerLogout;
import 'session/settings.dart' show ControllerSettings;
import 'state/grade_baseline.dart';
import 'state/read_scope.dart' show PendingFeatureRead;
import 'state/state.dart' show ControllerState, LocalDataOwnerScope;
import 'write/actions.dart' show ControllerWriteActions;
import 'write/lifecycle.dart' show ControllerWriteLifecycle;
import 'write/memory.dart' show ControllerWriteCache;
import 'write/readback.dart' show ControllerWriteReadbacks;
export 'state/types.dart' show AppPhase, SessionRecoveryStatus, LoginFormState;
export 'state/state.dart' show LocalDataOwnerScope;

/// 应用唯一的状态与通知实例；宿主仅使用公共查询、命令和扩展。
/// 局部实现共享同一账号代次、快照与写协调器，不建立独立通知代理。
class AppController extends ControllerState
    with
        ControllerLockDisplay,
        ControllerRefresh,
        ControllerProgressive,
        ControllerScheduleImport,
        ControllerScheduleWidgets,
        ControllerScheduledSession,
        ControllerReadbackDispatch,
        ControllerAcademicTerms,
        ControllerAcademicWeeks,
        ControllerCgyyPurposes,
        ControllerHomeSources,
        ControllerHomePresentation,
        ControllerGrades,
        ControllerWriteLifecycle,
        ControllerWriteCache,
        ControllerWriteReadbacks,
        ControllerDiagnostics,
        ControllerAppService,
        ControllerOfflineStartup,
        ControllerOfflineCache,
        ControllerAgenda,
        ControllerLocalData,
        ControllerLogout,
        ControllerCacheManagement,
        ControllerProfile,
        ControllerOfflineQuery,
        ControllerLocalReadOptions,
        ControllerOfflineGrades,
        ControllerDeferredRecovery,
        ControllerBackendRecovery,
        ControllerRecoveryRetry,
        ControllerNetworkRecovery,
        ControllerBusinessRetry,
        ControllerRequiredRecovery,
        ControllerServiceRecovery,
        ControllerAuthentication,
        ControllerAuthenticationCompletion,
        ControllerSettings,
        ControllerInteractiveAuthentication,
        ControllerLifecycleActions,
        ControllerFormActions,
        ControllerReadActions,
        ControllerWriteActions {
  int _homeProjectionGeneration = 0;

  /// 本地投影可以与会话恢复并行，交付时仍核对账号和读取范围。
  bool get homeTodoProjectionBlocked =>
      internalRoutePolicyInFlight || internalActivities.blocksHomeProjection;

  /// 纯本地投影沿用读取、账号和路线栅栏，不排入学校读取队列。
  Future<HomeTodoProjection> projectHomeTodos(HomeTodoRequest request) async {
    final scope = internalCaptureReadScope();
    final route = internalRoutePolicyGeneration;
    final policy = internalLoginForm.routePolicy;
    final account = internalLocalAccount?.id;
    final generation = ++_homeProjectionGeneration;
    bool current() =>
        scope.isCurrent &&
        !internalDisposed &&
        !internalIsSigningOut &&
        !homeTodoProjectionBlocked &&
        (internalPhase == AppPhase.home ||
            (internalPhase == AppPhase.checkingSession &&
                internalLocalAccount != null)) &&
        route == internalRoutePolicyGeneration &&
        policy == internalLoginForm.routePolicy &&
        account == internalLocalAccount?.id &&
        generation == _homeProjectionGeneration;
    final backend = internalBackend;
    if (!current() || backend is! HomeTodoBackend)
      throw const AgendaException(AgendaFailure.unavailable);
    final expectedRoute = switch (policy) {
      RoutePolicy.direct => ConnectionMode.direct,
      RoutePolicy.webvpn => ConnectionMode.webvpn,
      RoutePolicy.auto => null,
    };
    final safe = HomeTodoRequest(
      accountId: account,
      snapshots: {
        for (final e in request.snapshots.entries)
          if ((e.value.evidence == null ||
                  e.value.evidence!.accountId == account) &&
              (expectedRoute == null || e.value.resolvedRoute == expectedRoute))
            e.key:
                e.key == FeatureId.signin &&
                    internalRoutePolicyReadRevision >= 0 &&
                    (e.value.readContext?.requestRevision ?? -1) <=
                        internalRoutePolicyReadRevision
                ? e.value.copyWith(
                    details: readonlyFeatureDetails(e.value.details),
                  )
                : e.value,
      },
      now: request.now,
      currentWeek: request.currentWeek,
      currentWeekRoute: request.currentWeekRoute,
      reminder: request.reminder,
    );
    try {
      final value = await (backend as HomeTodoBackend).projectHomeTodos(safe);
      if (!current()) throw const AgendaException(AgendaFailure.superseded);
      return value.overlayFailure == null && internalAgendaFailure != null
          ? HomeTodoProjection(
              value.todos,
              overlayFailure: internalAgendaFailure,
            )
          : value;
    } on Object catch (error) {
      if (!current()) throw const AgendaException(AgendaFailure.superseded);
      // 后端离线读取代次变化（如共享账号重新绑定）只是取代了本次投影，宿主可稍后重算。
      if (error is BackendException &&
          error.code == UbaaErrorCode.operationConflict) {
        throw const AgendaException(AgendaFailure.superseded);
      }
      rethrow;
    }
  }

  IhomeService? _ihomeService;

  ReadHealthCloud? get healthCloudRead {
    final backend = internalBackend;
    if (backend is! HealthCloudBackend) return null;
    final read = (backend as HealthCloudBackend).healthCloud;
    if (read == null) return null;
    final session = internalCaptureSessionScope();
    return (year) => internalReadService(
      RecoveryTarget.healthCloud,
      DiagnosticOperation.healthCloudRead,
      () {
        if (!session.isCurrent) {
          throw const UiError(
            code: UbaaErrorCode.operationConflict,
            title: '登录状态已变化',
            message: '请重新打开健康云',
          );
        }
        return read(year);
      },
    );
  }

  UbaaBackend? _ihomeBackend;
  int? _ihomeEpoch;
  IhomeService? get ihomeService {
    final backend = internalBackend;
    if (backend is! IhomeBackend) return null;
    final epoch = internalLifecycleEpoch;
    if (!identical(backend, _ihomeBackend) || epoch != _ihomeEpoch) {
      _ihomeBackend = backend;
      _ihomeEpoch = epoch;
      _ihomeService = GuardedIhomeService(
        (backend as IhomeBackend).ihome,
        () =>
            !internalDisposed &&
            !internalIsSigningOut &&
            !internalInteractiveEngaged &&
            internalPhase == AppPhase.home &&
            internalLifecycleEpoch == epoch &&
            identical(internalBackend, backend),
        canWrite: () => !internalActivities.hasActive,
        onRejected: internalReportUserSchoolRejection,
        read: internalReadService,
        recordFailure: internalRecordServiceFailure,
        recordOutcome: internalRecordServiceOutcome,
      );
    }
    return _ihomeService;
  }

  CampusAccountService? _campusService;
  ScopedCloudPrintService? _cloudPrintService;
  UbaaBackend? _cloudPrintBackend;
  int? _cloudPrintEpoch;

  CloudPrintService? get cloudPrintService {
    final backend = internalBackend;
    if (backend is! CloudPrintProvider) return null;
    final epoch = internalLifecycleEpoch;
    if (!identical(backend, _cloudPrintBackend) || epoch != _cloudPrintEpoch) {
      _cloudPrintBackend = backend;
      _cloudPrintEpoch = epoch;
      _cloudPrintService = ScopedCloudPrintService(
        (backend as CloudPrintProvider).cloudPrint,
        () =>
            !internalDisposed &&
            !internalIsSigningOut &&
            !internalInteractiveEngaged &&
            internalPhase == AppPhase.home &&
            internalLifecycleEpoch == epoch &&
            identical(internalBackend, backend),
        internalWriteCoordinator,
        internalRecordServiceFailure,
        internalRecordServiceOutcome,
      );
    }
    return _cloudPrintService;
  }

  GuardedBhpanService? _bhpanService;
  UbaaBackend? _bhpanBackend;
  int? _bhpanEpoch;
  BhpanService? get bhpanService {
    final backend = internalBackend;
    if (backend is! BhpanProvider) return null;
    final epoch = internalLifecycleEpoch;
    if (!identical(backend, _bhpanBackend) || epoch != _bhpanEpoch) {
      _bhpanBackend = backend;
      _bhpanEpoch = epoch;
      _bhpanService = GuardedBhpanService(
        (backend as BhpanProvider).bhpan,
        () =>
            !internalDisposed &&
            !internalIsSigningOut &&
            !internalInteractiveEngaged &&
            internalPhase == AppPhase.home &&
            internalLifecycleEpoch == epoch &&
            identical(internalBackend, backend),
        readService: internalReadService,
        onRejected: internalReportUserSchoolRejection,
        recordFailure: internalRecordServiceFailure,
        recordOutcome: internalRecordServiceOutcome,
      );
    }
    return _bhpanService;
  }

  /// 诊断本地目标选择或交付失败。只有发起下载的服务仍有效时才保存。
  UiError recordBhpanDeliveryFailure(
    BhpanService service,
    Object error,
    StackTrace stack,
  ) {
    final active = _bhpanService;
    if (active == null || !identical(active, service) || !active.current()) {
      return UbaaErrorMapper.fromObject(error);
    }
    return internalRecordServiceFailure(
      error,
      DiagnosticOperation.bhpanDelivery,
      stack,
    );
  }

  UbaaBackend? _campusBackend;
  int? _campusEpoch;

  /// “我的”页面的在线读取；账号、会话或路线代次变化后旧绑定失效。
  /// SPOC 附件、我的提交与课件的读取和下载；按后端代次重建。
  SpocFilesService? _spocFilesService;
  //
  SpocFilesService? get spocFilesService {
    final backend = internalBackend;
    if (backend is! SpocFilesBackend) return null;
    return _spocFilesService ??= (backend as SpocFilesBackend).spocFiles;
  }

  CampusAccountService? get campusAccountService {
    final backend = internalBackend;
    if (backend is! CampusAccountBackend) return null;
    final epoch = internalLifecycleEpoch;
    if (!identical(backend, _campusBackend) || epoch != _campusEpoch) {
      _campusBackend = backend;
      _campusEpoch = epoch;
      _campusService = GuardedCampusAccountService(
        (backend as CampusAccountBackend).campusAccount,
        () =>
            !internalDisposed &&
            !internalIsSigningOut &&
            !internalInteractiveEngaged &&
            internalPhase == AppPhase.home &&
            internalLifecycleEpoch == epoch &&
            identical(internalBackend, backend),
        read: internalReadService,
        onRejected: internalReportUserSchoolRejection,
      );
    }
    return _campusService;
  }

  FinanceService? _financeService;
  UbaaBackend? _financeBackend;
  int? _financeEpoch;

  /// 财务数据读取；账号、会话或路线代次变化后旧绑定失效。
  FinanceService? get financeService {
    final backend = internalBackend;
    if (backend is! FinanceBackend) return null;
    final epoch = internalLifecycleEpoch;
    if (!identical(backend, _financeBackend) || epoch != _financeEpoch) {
      _financeBackend = backend;
      _financeEpoch = epoch;
      _financeService = GuardedFinanceService(
        (backend as FinanceBackend).finance,
        () =>
            !internalDisposed &&
            !internalIsSigningOut &&
            !internalInteractiveEngaged &&
            internalPhase == AppPhase.home &&
            internalLifecycleEpoch == epoch &&
            identical(internalBackend, backend),
        read: internalReadService,
        onRejected: internalReportUserSchoolRejection,
      );
    }
    return _financeService;
  }

  final _signinStatusRead = PendingFeatureRead();

  AppController({
    required UbaaBackend backend,
    bool privacyAccepted = true,
    BackendFactory? backendFactory,
    CredentialVault? credentialVault,
    LocalAccountStore? localAccountStore,
    TelemetryClient? telemetry,
    LocalDiagnostics? diagnostics,
    void Function(ReadSchedulerTrace trace)? onReadSchedulerTrace,
  }) : super(
         backend: backend,
         privacyAccepted: privacyAccepted,
         backendFactory: backendFactory,
         credentialVault: credentialVault,
         localAccountStore: localAccountStore,
         telemetry: telemetry,
         diagnostics: diagnostics,
         onReadSchedulerTrace: onReadSchedulerTrace,
       );
}

extension AppControllerLibraryLoans on AppController {
  bool get canReadLibraryLoans => internalBackend is LibraryLoansBackend;

  bool get canPrepareLibraryLoanRenew =>
      internalBackend is LibraryLoanWriteBackend;

  Future<List<LibraryLoan>> readLibraryLoans() {
    final session = internalCaptureSessionScope();
    final backend = session.backend;
    if (backend is! LibraryLoansBackend) {
      throw UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict);
    }
    return internalReadService(
      RecoveryTarget.library,
      DiagnosticOperation.read,
      () {
        if (!session.isCurrent) {
          throw UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict);
        }
        return (backend as LibraryLoansBackend).readLibraryLoans();
      },
    );
  }

  /// 准备单本续借的一次性意图；准备本身不发送写请求。
  ///
  /// Core 按记录标识重新读取目标资格与写后核对基线。
  Future<WriteIntent> prepareLibraryLoanRenew(String loanId) =>
      internalUserSchoolAction(() async {
        final backend = internalBackend;
        if (backend is! LibraryLoanWriteBackend) {
          throw const BackendException(UbaaErrorCode.unsupported);
        }
        final normalized = loanId.trim();
        if (normalized.isEmpty || normalized.length > 256) {
          throw const BackendException(UbaaErrorCode.invalidInput);
        }
        internalWriteCoordinator.ensureLibraryLoanCanPrepare(normalized);
        return (backend as LibraryLoanWriteBackend).prepareLibraryLoanRenew(
          loanId: normalized,
        );
      });
}

extension AppControllerSigninQr on AppController {
  bool get canFetchSigninQr => internalBackend is SigninQrBackend;

  bool get canCheckSigninStatus => internalBackend is SigninReadbackBackend;

  Future<bool> checkSigninSigned(String courseId) async {
    final target = courseId.trim();
    if (target.isEmpty) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    final result = await _signinStatusRead.joinOrStart(_readLatestSignin);
    final item = result.details
        .map((detail) => detail.presentation)
        .whereType<SigninPresentation>()
        .where((item) => item.actionTarget?.trim() == target)
        .firstOrNull;
    if (item == null) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    return item.signStatus == 1;
  }

  Future<FeatureResult> _readLatestSignin() async {
    const feature = FeatureId.signin;
    final scope = internalCaptureReadScope();
    final route = internalRoutePolicyGeneration;
    bool current() =>
        scope.isCurrent &&
        internalPhase == AppPhase.home &&
        internalAppForeground &&
        !internalReadTransitionBlocked &&
        route == internalRoutePolicyGeneration;
    final backend = scope.backend;
    if (backend is! SigninReadbackBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    if (!current()) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    final listContext = internalSnapshots[feature]?.readContext;
    final homeRevision =
        internalHomeDefaults[feature]?.readContext?.requestRevision;
    final result = await internalScheduleAuxiliaryRead(
      backend,
      feature,
      ReadPriority.urgent,
      current,
      (backend as SigninReadbackBackend).readSigninAfterWrite,
    );
    if (!current() ||
        internalSnapshots[feature]?.readContext?.requestRevision !=
            listContext?.requestRevision ||
        internalHomeDefaults[feature]?.readContext?.requestRevision !=
            homeRevision) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    if (result.error case final error?) throw BackendException.fromUi(error);
    final generation = internalNextFeatureGeneration(feature);
    final query = listContext?.query;
    final filterStatus = switch (query?.view) {
      FeatureQueryView.signinPending => 0,
      FeatureQueryView.signinCompleted => 1,
      _ => null,
    };
    final visible = filterStatus == null
        ? result
        : _filterSignin(result, filterStatus);
    internalAcceptHomeDefault(
      feature,
      result,
      FeatureReadContext(requestRevision: generation),
    );
    internalApplyFeatureResultIfCurrent(
      feature,
      visible,
      generation,
      scope.session.lifecycle,
      readContext: FeatureReadContext(
        query: query,
        requestRevision: generation,
      ),
    );
    internalAgendaEpoch++;
    internalNotify();
    return result;
  }

  FeatureResult _filterSignin(FeatureResult result, int status) {
    final details = result.details
        .where(
          (item) =>
              (item.presentation as SigninPresentation).signStatus == status,
        )
        .toList(growable: false);
    if (details.isEmpty)
      return FeatureResult.empty(resolvedRoute: result.resolvedRoute);
    final label = status == 1 ? '已上课' : '未上课';
    return FeatureResult.success(
      summary: '${details.length}门${label}课程',
      details: details,
      resolvedRoute: result.resolvedRoute,
    );
  }

  Future<SigninQr> fetchSigninQr(String courseId, Duration offset) async {
    final scope = internalLocalDataOwnerScope;
    scope.checkCurrent();
    final backend = internalBackend;
    if (backend is! SigninQrBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final route = internalRoutePolicyGeneration;
    final value = await (backend as SigninQrBackend).fetchSigninQr(
      courseId,
      offset,
    );
    scope.checkCurrent();
    if (!identical(internalBackend, backend) ||
        route != internalRoutePolicyGeneration) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    return value;
  }
}

extension AppControllerLockDisplay on AppController {
  Future<CgyyLockDisplaySession> openLockDisplay({bool userInitiated = true}) =>
      userInitiated
      ? internalUserSchoolAction(internalOpenLockDisplay)
      : internalAutomaticSchoolAction(internalOpenLockDisplay);

  Future<CgyyLockDisplay> readLockDisplay(
    CgyyLockDisplaySession session, {
    required bool userInitiated,
  }) => userInitiated
      ? internalUserSchoolAction(session.read)
      : internalAutomaticSchoolAction(session.read);
}

extension ScheduleWidgetCache on AppController {
  String? get scheduleWidgetOwner => internalScheduleWidgetOwner;
  Object get scheduleWidgetRevision => internalScheduleWidgetRevision;
  Future<ScheduleWidgetSnapshot> readScheduleWidgets(
    bool Function() publisherCurrent,
  ) => internalReadScheduleWidgets(publisherCurrent);
}

extension AppControllerLocalData on AppController {
  LocalDataOwnerScope get localDataOwnerScope => internalLocalDataOwnerScope;
}

/// 跟随控制器账号与缓存代次的加密基线，不另开学校客户端。
final class ControllerGradeScoreStore implements GradeScoreStore {
  ControllerGradeScoreStore(AppController controller)
    : _owner = GradeBaselineOwner(controller.internalCaptureOfflineScope);
  final GradeBaselineOwner _owner;
  @override
  Future<GradeScoreBaseline?> update(
    String account,
    ConnectionMode route,
    GradeScoreBaseline latest,
  ) => _owner.update(account, route, latest);
  @override
  Future<void> clearAccount(String account) => _owner.clearAccount(account);
}

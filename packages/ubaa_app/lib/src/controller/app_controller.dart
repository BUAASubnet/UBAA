import 'dart:async';
import 'home/presentation.dart';
import 'agenda/lifecycle.dart';
import 'state/types.dart' show AppPhase;
import 'features/ihome/service.dart';
import 'features/campus/service.dart';
import 'features/bhpan/service.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/lifecycle.dart';
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
import 'lifecycle/actions.dart' show ControllerActions;
import 'lifecycle/diagnostics.dart' show ControllerDiagnostics;
import 'reads/progressive.dart' show ControllerProgressive;
import 'reads/readback.dart' show ControllerReadbackDispatch;
import 'reads/session.dart' show ControllerScheduledSession;
import 'recovery/backend_rebuild.dart' show ControllerBackendRecovery;
import 'recovery/business_retry.dart' show ControllerBusinessRetry;
import 'recovery/grades.dart' show ControllerOfflineGrades;
import 'recovery/query.dart' show ControllerOfflineQuery;
import 'recovery/read_options.dart' show ControllerLocalReadOptions;
import 'recovery/required.dart' show ControllerRequiredRecovery;
import 'recovery/resume.dart' show ControllerDeferredRecovery;
import 'recovery/retry.dart' show ControllerRecoveryRetry;
import 'recovery/startup.dart' show ControllerOfflineStartup;
import 'session/completion.dart' show ControllerAuthenticationCompletion;
import 'session/authentication.dart' show ControllerAuthentication;
import 'session/interactive.dart' show ControllerInteractiveAuthentication;
import 'session/logout.dart' show ControllerLocalData, ControllerLogout;
import 'session/settings.dart' show ControllerSettings;
import 'state/grade_baseline.dart';
import 'state/state.dart' show ControllerState, LocalDataOwnerScope;
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
        ControllerBusinessRetry,
        ControllerRequiredRecovery,
        ControllerAuthentication,
        ControllerAuthenticationCompletion,
        ControllerSettings,
        ControllerInteractiveAuthentication,
        ControllerActions {
  int _homeProjectionGeneration = 0;

  /// 沿用 transition 计数，但扣除进行中的会话恢复所占的一个：投影只读取本机
  /// 已显示的缓存，账号若在恢复中被判定不符，交付前的账号与读取范围核对会丢弃结果。
  /// 其余过渡（原地登录、清缓存、写入等）仍阻塞纯本地投影。
  bool get homeTodoProjectionBlocked =>
      internalRoutePolicyInFlight ||
      internalWriteTransitions - (internalActiveRecovery != null ? 1 : 0) != 0;

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
            internalWriteTransitions == 0 &&
            internalLifecycleEpoch == epoch &&
            identical(internalBackend, backend),
      );
    }
    return _ihomeService;
  }

  CampusAccountService? _campusService;
  BhpanService? _bhpanService;
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
      );
    }
    return _bhpanService;
  }

  UbaaBackend? _campusBackend;
  int? _campusEpoch;

  /// “我的”页面的在线读取；账号、会话或路线代次变化后旧绑定失效。
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
      );
    }
    return _campusService;
  }

  AppController({
    required UbaaBackend backend,
    BackendFactory? backendFactory,
    CredentialVault? credentialVault,
    LocalAccountStore? localAccountStore,
    TelemetryClient? telemetry,
    LocalDiagnostics? diagnostics,
    void Function(ReadSchedulerTrace trace)? onReadSchedulerTrace,
  }) : super(
         backend: backend,
         backendFactory: backendFactory,
         credentialVault: credentialVault,
         localAccountStore: localAccountStore,
         telemetry: telemetry,
         diagnostics: diagnostics,
         onReadSchedulerTrace: onReadSchedulerTrace,
       );
}

extension AppControllerLockDisplay on AppController {
  Future<CgyyLockDisplaySession> openLockDisplay() => internalOpenLockDisplay();
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

import 'dart:async';
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
        ControllerGrades,
        ControllerWriteLifecycle,
        ControllerWriteCache,
        ControllerWriteReadbacks,
        ControllerDiagnostics,
        ControllerOfflineStartup,
        ControllerOfflineCache,
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

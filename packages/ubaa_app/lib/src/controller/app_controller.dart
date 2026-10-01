import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

import '../contracts/backend.dart';
import '../contracts/interactive_auth.dart';
import '../contracts/progressive.dart';
import '../contracts/schedule_import.dart';
import 'read_scheduler.dart';
import '../contracts/lifecycle.dart';
import '../contracts/offline.dart';
import '../contracts/profile.dart';
import '../contracts/cache_management.dart';
import '../contracts/query.dart';
import '../contracts/routing.dart';
import '../contracts/recovery.dart';
import '../contracts/write.dart';
import '../contracts/write_readback.dart';
import '../contracts/grade_baseline.dart';
import '../presentation/grades.dart';
import '../write/cgyy_validation.dart';
import '../write/coordinator.dart';
import '../write/receipt_verifier.dart';
import '../write/ygdk_validation.dart';
import 'error_mapper.dart';

part 'app_controller/cgyy_readback.dart';
part 'app_controller/evaluation_readback.dart';
part 'app_controller/refresh.dart';
part 'app_controller/read_tasks/progressive.dart';
part 'app_controller/read_tasks/judge_projection.dart';
part 'app_controller/schedule/import.dart';
part 'app_controller/read_tasks/session.dart';
part 'app_controller/read_tasks/readback.dart';
part 'app_controller/academic_terms.dart';
part 'app_controller/academic_weeks.dart';
part 'app_controller/cgyy_purposes.dart';
part 'app_controller/home_sources.dart';
part 'app_controller/grades.dart';
part 'app_controller/write_lifecycle.dart';
part 'app_controller/write_cache/memory.dart';
part 'app_controller/write_cache/readback.dart';
part 'app_controller/ygdk_readback.dart';
part 'app_controller/diagnostics.dart';
part 'app_controller/offline_startup.dart';
part 'app_controller/offline/cache.dart';
part 'app_controller/offline/logout.dart';
part 'app_controller/cache_management/controller.dart';
part 'app_controller/offline/profile.dart';
part 'app_controller/offline/query.dart';
part 'app_controller/offline/read_options.dart';
part 'app_controller/offline/grades.dart';
part 'app_controller/grades/baseline_store.dart';
part 'app_controller/offline/resume.dart';
part 'app_controller/offline/backend_rebuild.dart';
part 'app_controller/offline/retry.dart';
part 'app_controller/offline/business_retry.dart';
part 'app_controller/offline/required.dart';
part 'app_controller/authentication.dart';
part 'app_controller/settings.dart';
part 'app_controller/interactive_auth.dart';

enum AppPhase { splash, checkingSession, login, loggingIn, home }

enum SessionRecoveryStatus {
  idle,
  restoring,
  ready,
  unavailable,
  needsLogin,
  signedOut,
}

@immutable
class LoginFormState {
  const LoginFormState({
    this.username = '',
    this.password = '',
    this.captcha = '',
    this.rememberPassword = false,
    this.autoLogin = false,
    this.routePolicy = RoutePolicy.auto,
  });

  final String username;
  final String password;
  final String captcha;
  final bool rememberPassword;
  final bool autoLogin;
  final RoutePolicy routePolicy;

  LoginFormState copyWith({
    String? username,
    String? password,
    String? captcha,
    bool? rememberPassword,
    bool? autoLogin,
    RoutePolicy? routePolicy,
  }) => LoginFormState(
    username: username ?? this.username,
    password: password ?? this.password,
    captcha: captcha ?? this.captcha,
    rememberPassword: rememberPassword ?? this.rememberPassword,
    autoLogin: autoLogin ?? this.autoLogin,
    routePolicy: routePolicy ?? this.routePolicy,
  );
}

/// 应用状态协调器。UI 只订阅此类，不直接持有 FRB handle 或平台存储对象。
class AppController extends ChangeNotifier {
  AppController({
    required UbaaBackend backend,
    BackendFactory? backendFactory,
    CredentialVault? credentialVault,
    LocalAccountStore? localAccountStore,
    FileGradeScoreStore? legacyGradeScores,
    TelemetryClient? telemetry,
    LocalDiagnostics? diagnostics,
    void Function(ReadSchedulerTrace trace)? onReadSchedulerTrace,
  }) : _backend = backend,
       _backendFactory = backendFactory,
       _credentialVault = credentialVault ?? const NoopCredentialVault(),
       _localAccountStore = localAccountStore,
       _legacyGradeScores = legacyGradeScores,
       _telemetry = telemetry ?? const NoopTelemetryClient(),
       _diagnostics = diagnostics ?? LocalDiagnostics(),
       _telemetryEnabled = (telemetry ?? const NoopTelemetryClient()).enabled,
       _snapshots = {
         for (final feature in FeatureId.values)
           feature: FeatureSnapshot(feature: feature),
       } {
    _writeCoordinator = _createWriteCoordinator(backend);
    _readScheduler = ReadScheduler(
      canRun: _canRunScheduledRead,
      onTrace: onReadSchedulerTrace,
    );
    _writeCoordinator.addListener(_notify);
  }

  UbaaBackend _backend;
  final BackendFactory? _backendFactory;
  final CredentialVault _credentialVault;
  final LocalAccountStore? _localAccountStore;
  final FileGradeScoreStore? _legacyGradeScores;
  LocalAccount? _localAccount;
  bool _isSigningOut = false;
  bool _credentialRestoreAllowed = true;
  bool _manualAuthenticationRequired = false;
  int _loginFormRevision = 0;
  int _loginCredentialRevision = 0;
  int _interactiveGeneration = 0;
  bool _interactiveInPlace = false;
  bool _interactiveEngaged = false;
  LoginVerificationState? _loginVerification;
  final Map<ConnectionMode, Timer> _captchaTimers = {};
  int _routePolicyGeneration = 0;
  bool _routePolicyInFlight = false;
  Completer<void>? _backendRebuildCompletion;
  Future<void>? _credentialMutation;
  bool _clearingBusinessCache = false;
  int _businessCacheEpoch = 0;
  bool get isClearingBusinessCache => _clearingBusinessCache;
  bool get canClearBusinessCache =>
      cacheAccountId != null &&
      !_disposed &&
      !_clearingBusinessCache &&
      !_interactiveEngaged &&
      !isLoggingIn &&
      !_rebuildingBackend &&
      _writeTransitions == 0 &&
      _activeRecovery == null &&
      !_writeCoordinator.hasPendingOperation;
  int get businessCacheEpoch => _businessCacheEpoch;
  String? get cacheAccountId =>
      _phase == AppPhase.home &&
          !_isSigningOut &&
          _backend is CacheManagementBackend
      ? _localAccount?.id
      : null;
  Future<CacheUsageSummary> cacheUsage({required String accountId}) =>
      _readCacheUsage(accountId);
  Future<CacheClearOutcome> clearBusinessCache({required String accountId}) =>
      _clearControllerCache(accountId);
  bool _automaticCredentialBlocked = false;
  bool _appForeground = true;
  final _recoveryRetries = <FeatureId, _RecoveryRetry>{};
  final _businessRetries = <(FeatureId, bool), _BusinessRetry>{};
  Timer? _networkWakeCooldown;
  final _queuedRecoveries = <FeatureId, _RecoveryRequest>{};
  _RecoveryRequest? _activeRecovery;
  ConnectionMode? _recoveredRoute;
  final _featureRecoveryStates = <FeatureId, SessionRecoveryStatus>{};
  final _featureRecoveryErrors = <FeatureId, UiError>{};
  int _readRequestRevision = 0;
  SessionRecoveryStatus recoveryStatusFor(FeatureId feature) =>
      _featureRecoveryStates[feature] ?? SessionRecoveryStatus.idle;
  ConnectionMode? get recoveredRoute => _recoveredRoute;
  bool _deferredRecoveryScheduled = false;
  int? _pendingHomeRecoveryEpoch;
  Future<void> _offlineOpenFuture = Future<void>.value();
  int _offlineAccountEpoch = 0;
  UiError? _localCacheError;
  UiError? get localCacheError => _localCacheError;
  List<WriteReadbackHint> _writeReadbacks = const [];
  List<WriteReadbackHint> get writeReadbacks =>
      List.unmodifiable(_writeReadbacks);
  UiError? _writeReadbackError;
  UiError? get writeReadbackError => _writeReadbackError;
  int _writeReadbackRevision = 0, _writeReadbackLoadedEpoch = -1;
  _WriteReadbackRead? _writeReadbackRead;
  Future<void> refreshWriteReadbacks() => _loadWriteReadbacks(force: true);
  Future<void> dismissWriteReadback(String id) =>
      _dismissControllerReadback(id);
  bool _usesLocalRecovery = false;
  SessionRecoveryStatus _sessionRecoveryStatus = SessionRecoveryStatus.idle;
  Future<void>? _sessionRecoveryFuture;
  bool _homeFrameReported = false;
  bool _inPlaceLogin = false;
  bool get isLoggingIn => _inPlaceLogin || _phase == AppPhase.loggingIn;
  SessionRecoveryStatus get sessionRecoveryStatus => _sessionRecoveryStatus;
  bool get usesLocalRecovery => _usesLocalRecovery;

  /// 宿主在首页首帧之后调用；旧自动登录选项不参与是否开始检查的判断。
  void onHomeFirstFrame() {
    if (_homeFrameReported || !_usesLocalRecovery || _phase != AppPhase.home)
      return;
    _homeFrameReported = true;
    if (_sessionRecoveryStatus == SessionRecoveryStatus.idle) {
      unawaited(recoverSession());
    }
  }

  Future<void> recoverSession({
    FeatureId feature = FeatureId.schedule,
    bool refreshHomeAfter = true,
  }) => _recoverSession(feature: feature, refreshHomeAfter: refreshHomeAfter);

  /// 生命周期只更新可见状态；后台不开始未发送的恢复或首页同步。
  void setAppForeground(bool foreground) {
    _appForeground = foreground;
    if (!foreground) _cancelLoginVerification();
    if (foreground) _drainDeferredRecovery();
    _syncRecoveryRetries();
    _pumpReadTasks();
  }

  /// 本地网络变化只是唤醒提示，成功与否仍由原会话检查判断。
  void onNetworkChanged() => _wakeNetworkRecovery();

  /// 返回前台复用当前实例；旧宿主已认证首页也转入同一恢复协调路径。
  Future<void> resumeSession() {
    if (_disposed || _phase != AppPhase.home || _isSigningOut)
      return Future<void>.value();
    if (!_usesLocalRecovery) {
      _usesLocalRecovery = true;
      _sessionRecoveryStatus = SessionRecoveryStatus.ready;
    }
    return _recoverSession();
  }

  final TelemetryClient _telemetry;
  final LocalDiagnostics _diagnostics;
  final Map<FeatureId, FeatureSnapshot> _snapshots;
  late WriteCoordinator _writeCoordinator;
  late final ReadScheduler _readScheduler;
  final _readScopes = <_ProgressiveScope>{};
  final _scheduleImportScopes = <String, _ScheduleImportScope>{};
  final _scheduleImports = <String, ScheduleImportState>{};
  int _scheduleImportEpoch = -1;
  Map<String, ScheduleImportState> get scheduleImports =>
      Map.unmodifiable(_scheduleImports);
  bool get canSaveScheduleSemester =>
      !_disposed &&
      !_isSigningOut &&
      !_clearingBusinessCache &&
      _phase == AppPhase.home &&
      _localAccount != null &&
      _backend is ScheduleImportBackend;
  Future<void> saveScheduleSemester(String term) => _saveScheduleSemester(term);
  void cancelScheduleImport(String term) => _cancelScheduleImport(term);
  int _writeTransitions = 0;
  final _writeRefreshes = <FeatureId, _WriteRefreshRequest>{};
  bool _writeRefreshScheduled = false;

  AppPhase _phase = AppPhase.splash;
  LoginFormState _loginForm = const LoginFormState();
  UserSummary? _user;
  UserSummary? _profileDisplay;
  int _profileDisplayEpoch = -1,
      _profileRefreshedEpoch = -1,
      _profileFailureEpoch = -1;
  DateTime? _profileRefreshedAt;
  RoutePolicy? _profileRefreshedPolicy;
  _ProfileRequest? _profileRequest;
  UiError? _error;
  bool _disposed = false;
  bool _initialized = false;
  final Map<FeatureId, int> _featureRefreshGenerations = <FeatureId, int>{
    for (final feature in FeatureId.values) feature: 0,
  };
  final _homeDefaults = <FeatureId, FeatureSnapshot>{
    for (final feature in FeatureId.values)
      feature: FeatureSnapshot(feature: feature),
  };
  _HomeSupplementCache? _homeSupplementCache;
  _GradesReadCache? _gradesReadCache;
  _AcademicWeeksCache? _academicWeeksCache;
  _CgyyPurposeCache? _cgyyPurposeCache;
  FeatureResult? _academicTermsResult;
  Future<FeatureResult>? _academicTermsPending;
  ReadDemand? _academicTermsDemand;
  UbaaBackend? _academicTermsBackend;
  int _academicTermsEpoch = -1;
  int _academicTermsLifecycle = -1;
  int _academicTermsSerial = 0;
  int _lifecycleEpoch = 0;
  int _readCacheEpoch = 0;

  /// UI 返回帧缓存的失效代次；不改变当前可见旧快照的 stale 语义。
  int get readCacheEpoch => _readCacheEpoch;
  int _ygdkGeneration = 0;
  bool _telemetryEnabled;
  YgdkReadbackState _ygdkReadbackState = const YgdkReadbackState.empty();
  List<ConnectionMode> _activeRoutes = const <ConnectionMode>[];
  bool _rebuildingBackend = false;

  /// Expando 按实例身份关联释放 Future，且不会因去重表阻止已释放
  /// backend 被回收。
  final Expando<Future<void>> _backendDisposals = Expando<Future<void>>();

  AppPhase get phase => _phase;
  LoginFormState get loginForm => _loginForm;
  LoginVerificationState? get loginVerification => _loginVerification;
  void setCaptchaAnswer(ConnectionMode route, String answer) =>
      _setCaptchaAnswer(route, answer);
  Future<void> refreshCaptcha(ConnectionMode route) => _refreshCaptcha(route);
  Future<void> continueReadyLogin(ConnectionMode route) =>
      _continueReadyLogin(route);
  Future<void> continueWithFixedReadyRoute(ConnectionMode route) =>
      _continueReadyLogin(route, pinRoute: true);
  void cancelLoginVerification() => _cancelLoginVerification();
  UserSummary? get user => _user;

  /// 宿主仅用于展示；认证、提醒归属和写入仍使用user。
  UserSummary? get displayUser {
    if (_isSigningOut) return null;
    if (_phase != AppPhase.home || _user == null) return _user;
    final account = _localAccount;
    if (account == null) return _user;
    if (_profileDisplay?.accountScope == account.id) return _profileDisplay;
    return profileDisplay(_user!, null, null, accountScope: account.id);
  }

  UiError? get error => _error;
  bool get telemetryEnabled => _telemetryEnabled;

  /// 实际客户端能力与本地开关分离；关闭本地开关不销毁已配置的客户端。
  bool get telemetryAvailable => _telemetry.enabled;
  bool get credentialPersistenceAvailable => _credentialVault.isAvailable;
  List<ConnectionMode> get activeRoutes =>
      List<ConnectionMode>.unmodifiable(_activeRoutes);
  bool get isRebuildingBackend => _rebuildingBackend;
  Map<FeatureId, FeatureSnapshot> get snapshots =>
      Map<FeatureId, FeatureSnapshot>.unmodifiable(_snapshots);
  YgdkReadbackState get ygdkReadbackState => _ygdkReadbackState;
  WriteCoordinator get writeCoordinator => _writeCoordinator;
  LocalDiagnostics get diagnostics => _diagnostics;

  /// 只导出本次运行允许字段，不读取凭据、业务输入或磁盘会话。
  String exportDiagnostics() => _diagnostics.exportText();

  /// backend 必须同时提供 typed 写入与原路线回读，宿主才可暴露
  /// 阳光打卡提交入口。平台照片能力仍由宿主另行检查。
  bool get hasYgdkSubmissionBackendCapabilities =>
      _backend is YgdkWriteBackend && _backend is YgdkSubmissionReadbackBackend;

  /// backend 必须同时提供 typed 写入与调用方固定路线回读，
  /// 宿主才能暴露评教提交入口。
  bool get hasEvaluationSubmissionBackendCapabilities =>
      _backend is EvaluationWriteBackend &&
      _backend is EvaluationSubmissionReadbackBackend;

  Future<void> initialize() => _initializeController();

  /// 在 Dart isolate 或宿主生命周期重建后替换 opaque backend。
  ///
  /// 新 backend 成功创建后才 dispose 旧 backend；随后重新读取 Core 的路线和
  ///认证状态。没有提供工厂、正在登录/重建或 controller 已销毁时返回 `false`，
  ///不伪造恢复成功。
  Future<bool> rebuildBackend() async {
    final factory = _backendFactory;
    if (factory == null ||
        _disposed ||
        _rebuildingBackend ||
        isLoggingIn ||
        _sessionRecoveryFuture != null ||
        _writeTransitions != 0 ||
        _writeCoordinator.hasPendingOperation)
      return false;
    // 初始化正在读取旧 backend 的认证/路线状态时，生命周期重建会与旧
    // handle 竞争并可能把结果写入新实例；等待初始化完成后再由下一次
    // resumed 事件触发重建。
    if (_phase == AppPhase.loggingIn || _phase == AppPhase.checkingSession) {
      return false;
    }
    final previousLoginError = _phase == AppPhase.login ? _error : null;
    final errorRevision = _loginFormRevision;
    final completion = Completer<void>();
    _backendRebuildCompletion = completion;
    _cancelLoginVerification(notify: false);
    _releaseLoginSecret();
    _rebuildingBackend = true;
    _beginWriteTransition();
    _setPhase(AppPhase.checkingSession);
    try {
      final replacement = factory();
      if (identical(replacement, _backend)) {
        _error = UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
        _setPhase(AppPhase.login);
        return false;
      }
      final previous = _backend;
      try {
        await _disposeBackendOnce(previous);
      } on Object catch (error, stackTrace) {
        // 新实例已经创建；旧实例清理失败不能让新实例继续持有旧状态。
        _recordFailure(
          error,
          DiagnosticOperation.disposal,
          stackTrace: stackTrace,
        );
      }
      if (_disposed) {
        try {
          await _disposeBackendOnce(replacement);
        } on Object {
          // controller 已销毁时尽力释放新实例，不能向 UI 抛出异常。
        }
        return false;
      }
      _backend = replacement;
      _replaceWriteCoordinator(replacement);
      _initialized = false;
      _user = null;
      _activeRoutes = const <ConnectionMode>[];
      _resetFeatureSnapshots();
      await _initializeController(
        previousLoginError: _loginFormRevision == errorRevision
            ? previousLoginError
            : null,
      );
      return true;
    } on BackendException catch (exception, stackTrace) {
      _error = _recordFailure(
        exception,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
      _setPhase(AppPhase.login);
      return false;
    } on Object catch (error, stackTrace) {
      _error = _recordFailure(
        error,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
      _setPhase(AppPhase.login);
      return false;
    } finally {
      _endWriteTransition();
      _backendRebuildCompletion = null;
      completion.complete();
      _rebuildingBackend = false;
      _notify();
    }
  }

  void setUsername(String value) {
    if (_disposed || isLoggingIn || _isSigningOut) return;
    final accountChanged = value.trim() != _loginForm.username.trim();
    if (accountChanged)
      _cancelLoginVerification(releasePassword: false, notify: false);
    if (accountChanged) _manualAuthenticationRequired = true;
    _loginFormRevision++;
    _loginCredentialRevision++;
    _loginForm = _loginForm.copyWith(
      username: value,
      password: accountChanged ? '' : null,
      captcha: accountChanged ? '' : null,
    );
    _error = null;
    _notify();
  }

  void setPassword(String value) {
    if (_disposed || isLoggingIn || _isSigningOut) return;
    if (value != _loginForm.password)
      _cancelLoginVerification(releasePassword: false, notify: false);
    _loginFormRevision++;
    _loginCredentialRevision++;
    _loginForm = _loginForm.copyWith(password: value);
    _error = null;
    _notify();
  }

  void setCaptcha(String value) {
    if (_disposed || isLoggingIn || _isSigningOut) return;
    _loginFormRevision++;
    _loginCredentialRevision++;
    _loginForm = _loginForm.copyWith(captcha: value);
    _error = null;
    _notify();
  }

  void setRememberPassword(bool value) {
    if (!_canEditLoginOptions) return;
    _loginFormRevision++;
    _loginForm = _loginForm.copyWith(
      rememberPassword: value,
      autoLogin: value ? _loginForm.autoLogin : false,
    );
    _notify();
  }

  void setAutoLogin(bool value) {
    if (!_canEditLoginOptions) return;
    _loginFormRevision++;
    _loginForm = _loginForm.copyWith(
      autoLogin: value,
      rememberPassword: value ? true : _loginForm.rememberPassword,
    );
    _notify();
  }

  Future<void> setRoutePolicy(RoutePolicy value) =>
      _setRoutePolicyController(value);

  Future<void> submitLogin({bool preserveHome = false}) {
    if (_backend case final InteractiveLoginBackend backend) {
      if (_disposed ||
          _isSigningOut ||
          _rebuildingBackend ||
          _sessionRecoveryFuture != null ||
          _writeCoordinator.hasPendingOperation ||
          _writeTransitions != 0)
        return Future.value();
      if (!_interactiveEngaged)
        _interactiveInPlace = preserveHome && _phase == AppPhase.home;
      return _submitInteractiveLogin(backend);
    }
    return _submitLoginController(preserveHome: preserveHome);
  }

  /// 用户明确请求学期选项，不占用全局课表快照。
  Future<FeatureResult> loadAcademicTerms({bool forceRefresh = false}) =>
      _localFirstOptions(
        const FeatureQuery(view: FeatureQueryView.scheduleTerms),
        forceRefresh,
        () => _loadAcademicTerms(forceRefresh: forceRefresh),
      );

  /// 教学周选项按原学期独立读取，不覆盖当前课表或查询草稿。
  Future<FeatureResult> loadAcademicWeeks(
    String term, {
    bool forceRefresh = false,
  }) => _localFirstOptions(
    FeatureQuery(view: FeatureQueryView.scheduleWeeks, term: term),
    forceRefresh,
    () => _loadAcademicWeeks(term, forceRefresh: forceRefresh),
  );

  /// 活动类型独立读取，不覆盖研讨室日时段和已选目标。
  Future<FeatureResult> loadCgyyPurposes({bool forceRefresh = false}) =>
      _localFirstOptions(
        const FeatureQuery(view: FeatureQueryView.cgyyPurposeTypes),
        forceRefresh,
        () => _loadCgyyPurposes(forceRefresh: forceRefresh),
        feature: FeatureId.cgyy,
      );

  /// 成绩统计的独立读取，不改变当前页面的查询或详情帧。
  Future<FeatureResult> loadGradeTerm(
    String term, {
    bool forceRefresh = false,
  }) => _loadGradeTerm(term, forceRefresh: forceRefresh);

  Future<GradesAggregate> loadAllGrades({
    bool forceRefresh = false,
    void Function(GradesAggregate)? onProgress,
  }) =>
      _loadGradesWithCache(forceRefresh: forceRefresh, onProgress: onProgress);

  /// 首页变化检查只读取唯一标为当前的学期；缺失时不猜第一项。
  Future<GradeTermRead?> loadCurrentGrades({
    bool forceRefresh = false,
    bool background = false,
  }) => _loadCurrentGrades(
    forceRefresh: forceRefresh,
    priority: background ? ReadPriority.background : ReadPriority.interactive,
  );

  /// 首页默认来源与领域当前查询隔离；不授予额外写资格。
  Map<FeatureId, FeatureSnapshot> get homeSnapshots =>
      Map.unmodifiable(_homeDefaults);

  Future<FeatureResult> loadHomeSupplement(
    HomeSupplement source, {
    bool forceRefresh = false,
  }) => _loadHomeSupplement(source, forceRefresh: forceRefresh);

  Future<void> refreshHome({Iterable<FeatureId>? only}) =>
      _refreshHome(only: only);

  Future<void> retryFeature(FeatureId feature) {
    final query = _snapshots[feature]?.readContext?.query;
    return query == null
        ? refreshHome(only: <FeatureId>[feature])
        : refreshFeatureQuery(feature, query);
  }

  /// 对支持 [FeatureQueryBackend] 的生产实现执行单领域筛选读取。
  Future<void> refreshFeatureQuery(FeatureId feature, FeatureQuery query) =>
      _refreshFeatureQuery(feature, query);

  /// 准备博雅选课/退选的 typed 一次性意图；准备本身不提交写请求。
  Future<WriteIntent> prepareBykcWrite(
    WriteOperation operation,
    int courseId,
  ) async {
    final backend = _backend;
    if (backend is! BykcWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final writer = backend as BykcWriteBackend;
    if (courseId <= 0) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return switch (operation) {
      WriteOperation.bykcSelectCourse => writer.prepareBykcSelectCourse(
        courseId: courseId,
      ),
      WriteOperation.bykcDeselectCourse => writer.prepareBykcDeselectCourse(
        courseId: courseId,
      ),
      _ => throw const BackendException(UbaaErrorCode.invalidInput),
    };
  }

  /// 准备博雅签到/签退；仅接受冻结合同的 signType 1/2 和完整有效坐标对。
  Future<WriteIntent> prepareBykcSignWrite(
    int courseId,
    int signType, {
    double? lat,
    double? lng,
  }) async {
    final backend = _backend;
    if (backend is! BykcWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final hasNoCoordinates = lat == null && lng == null;
    final hasValidCoordinates =
        lat != null &&
        lng != null &&
        lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
    if (courseId <= 0 ||
        (signType != 1 && signType != 2) ||
        (!hasNoCoordinates && !hasValidCoordinates)) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    final writer = backend as BykcWriteBackend;
    return writer.prepareBykcSignCourse(
      courseId: courseId,
      lat: lat,
      lng: lng,
      signType: signType,
    );
  }

  /// 准备课堂签到的 typed 一次性意图；目标和资格必须来自读取白名单。
  Future<WriteIntent> prepareSigninWrite(SigninPerformAction action) async {
    final backend = _backend;
    if (backend is! SigninWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final writer = backend as SigninWriteBackend;
    final normalized = action.scheduleId.trim();
    if (normalized.isEmpty || action.eligibility != ActionEligibility.allowed) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return writer.prepareSigninPerform(courseId: normalized);
  }

  /// 准备场馆取消的一次性意图；只接受 Core 给出的 typed 目标。
  Future<WriteIntent> prepareCgyyCancelWrite(CgyyCancelAction action) async {
    final backend = _backend;
    if (backend is! CancellationWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    if (!action.hasCanonicalTarget) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return (backend as CancellationWriteBackend).prepareCgyyCancelOrder(
      id: action.orderId,
    );
  }

  /// 准备图书馆取消意图；目标、资格与分页上下文全部来自 Core typed 读取。
  Future<WriteIntent> prepareLibbookCancelWrite(
    LibbookCancelAction action,
  ) async {
    final backend = _backend;
    if (backend is! CancellationWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final bookingId = action.bookingId.trim();
    if (action.eligibility != ActionEligibility.allowed ||
        bookingId.isEmpty ||
        action.page <= 0 ||
        action.limit <= 0) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    final writer = backend as CancellationWriteBackend;
    return writer.prepareLibbookCancelBooking(
      id: bookingId,
      page: action.page,
      limit: action.limit,
    );
  }

  /// 准备图书馆预约的 typed 一次性意图；只接受读取白名单中的完整目标。
  Future<WriteIntent> prepareLibbookReserveWrite(
    LibbookReserveAction action,
  ) async {
    final backend = _backend;
    if (backend is! LibbookWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final values = <String>[
      action.areaId,
      action.seatId,
      action.day,
      action.segment,
      action.startTime,
      action.endTime,
    ].map((value) => value.trim()).toList(growable: false);
    if (action.eligibility != ActionEligibility.allowed ||
        values.any((value) => value.isEmpty)) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    final writer = backend as LibbookWriteBackend;
    return writer.prepareLibbookReserve(
      areaId: values[0],
      seatId: values[1],
      day: values[2],
      segment: values[3],
      startTime: values[4],
      endTime: values[5],
    );
  }

  /// 准备阳光打卡写意图；照片字节只复制到本次内存请求，不落盘或写日志。
  Future<WriteIntent> prepareYgdkWrite(YgdkSubmitInput input) async {
    final backend = _backend;
    if (backend is! YgdkWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    return (backend as YgdkWriteBackend).prepareYgdkSubmit(
      validateYgdkSubmitInput(input),
    );
  }

  /// 准备研讨室预约写意图；只接受 Core 已核对的 typed actions。
  Future<WriteIntent> prepareCgyySubmitWrite(CgyySubmitInput input) async {
    final backend = _backend;
    if (backend is! CgyyWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    return (backend as CgyyWriteBackend).prepareCgyySubmitReservation(
      validateCgyySubmitInput(input),
    );
  }

  /// 准备教学评教写意图；仅接受读取 action 中的 typed 目标。
  Future<WriteIntent> prepareEvaluationWrite(
    List<EvaluationSubmitTarget> targets,
  ) async {
    final backend = _backend;
    if (backend is! EvaluationWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final normalized = targets
        .map(_normalizeEvaluationTarget)
        .toList(growable: false);
    final uniqueKeys = normalized.map((target) => target.selectionKey).toSet();
    if (normalized.isEmpty ||
        normalized.any((target) => !target.hasRequiredIdentity) ||
        uniqueKeys.length != normalized.length) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return (backend as EvaluationWriteBackend).prepareEvaluationSubmitCourses(
      normalized,
    );
  }

  /// 提交已确认的一次性意图；不接受任意请求正文，也不自动重试。
  Future<WriteCommitResult> commitWrite(String intentId) =>
      _commitWriteWithBackend(_backend, intentId);

  /// 释放尚未确认的一次性意图；该操作不提交任何上游写请求。
  Future<void> discardWriteIntent(String intentId) =>
      _discardWriteWithBackend(_backend, intentId);

  /// 写入成功后仅刷新关联只读领域，用于结果核对；不会重试写请求。
  Future<void> refreshAfterWrite(
    WriteOperation operation, [
    FeatureQuery? readbackQuery,
  ]) => _refreshAfterWrite(operation, readbackQuery);

  /// 在场馆订单刷新完成后，仅按公开订单编号匹配提交收据。
  ///
  /// 该方法不发起额外请求，调用方必须先等待 [refreshAfterWrite]；读取失败、
  /// 空结果或不匹配均返回 `false`，绝不把写入结果升级为已核对。
  Future<bool> matchesCgyyReceipt(CgyyReservationReceipt receipt) async {
    if (receipt.orderId <= 0) return false;
    final snapshot = _snapshots[FeatureId.cgyy];
    if (snapshot == null || snapshot.status != FeatureLoadStatus.success) {
      return false;
    }
    final orderId = receipt.orderId.toString();
    return snapshot.details.any(
      (detail) => detail.fields.any(
        (field) => field.label == '订单编号' && field.value == orderId,
      ),
    );
  }

  /// 在 intent 的实际路线上执行场馆取消列表+详情双回读。
  Future<bool> verifyCgyyCancellation({
    required int orderId,
    required ConnectionMode expectedRoute,
  }) => _verifyCgyyCancellation(
    this,
    orderId: orderId,
    expectedRoute: expectedRoute,
  );

  /// 在 intent 的实际路线 best-effort 刷新阳光打卡概览与首页记录。
  ///
  /// 冻结来源没有提供记录与本次写入的严格关联规则，因此该方法不
  /// 接收收据也不返回核对结论，更不得将 OutcomeUnknown 升级为成功。
  Future<void> refreshYgdkAfterWrite({required ConnectionMode expectedRoute}) =>
      _refreshYgdkAfterWrite(this, expectedRoute: expectedRoute);

  /// 在 intent 的实际路线 best-effort 刷新评教课程。
  ///
  /// 该回读只更新 Evaluation 快照，不改写结果，也不会重试提交。
  Future<void> refreshEvaluationAfterWrite({
    required ConnectionMode expectedRoute,
  }) => _refreshEvaluationAfterWrite(this, expectedRoute: expectedRoute);

  Future<void> logout({
    bool clearSavedCredential = false,
    Future<void> Function()? clearLocalData,
  }) => _logoutController(
    clearSavedCredential: clearSavedCredential,
    clearLocalData: clearLocalData,
  );

  Future<void> setTelemetryEnabled(bool value) =>
      _setTelemetryEnabledController(value);

  Future<void> clearTelemetryQueue() async {
    await _flushTelemetry();
  }

  void clearError() {
    _clearError();
  }

  void _clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  bool _routePolicyHasSession(
    RoutePolicy policy,
    List<ConnectionMode> activeRoutes,
  ) => switch (policy) {
    RoutePolicy.auto => activeRoutes.isNotEmpty,
    RoutePolicy.direct => activeRoutes.contains(ConnectionMode.direct),
    RoutePolicy.webvpn => activeRoutes.contains(ConnectionMode.webvpn),
  };

  void _applyRouteSettings(BackendRouteSettings settings) {
    _activeRoutes = List<ConnectionMode>.unmodifiable(settings.activeRoutes);
    _loginForm = _loginForm.copyWith(routePolicy: settings.defaultPolicy);
  }

  Future<void> _refreshRouteSettings() async {
    if (_backend case final RouteSettingsBackend routeBackend) {
      try {
        final settings = await routeBackend.routeSettings();
        if (_disposed) return;
        _applyRouteSettings(settings);
      } on Object catch (error, stackTrace) {
        if (_disposed) return;
        // 登录已经成功时，路线状态读取失败不能把账号重新置为失败；清空
        // 不确定的活动槽位，后续读取仍由 Core 返回实际错误。
        _activeRoutes = const <ConnectionMode>[];
        _recordFailure(
          error,
          DiagnosticOperation.routeChange,
          stackTrace: stackTrace,
        );
      }
    }
  }

  void _setPhase(AppPhase phase) {
    if (phase == AppPhase.login) {
      _readCacheEpoch++;
      _lifecycleEpoch++;
      _ygdkGeneration++;
      _writeCoordinator.invalidate();
    }
    _phase = phase;
    _notify();
  }

  void _notify() {
    _syncRecoveryRetries();
    _drainDeferredRecovery();
    _pumpReadTasks();
    if (!_disposed) notifyListeners();
  }

  Future<void> _disposeBackendOnce(UbaaBackend backend) {
    final existing = _backendDisposals[backend];
    if (existing != null) return existing;
    if (backend is! BackendLifecycle) return Future<void>.value();
    final lifecycle = backend as BackendLifecycle;

    final completer = Completer<void>();
    _backendDisposals[backend] = completer.future;
    try {
      lifecycle.dispose().then<void>(
        (_) => completer.complete(),
        onError: (Object error, StackTrace stackTrace) {
          completer.completeError(error, stackTrace);
        },
      );
    } on Object catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
    return completer.future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _cancelLoginVerification(notify: false);
    _disposed = true;
    for (final scope in _readScopes.toList()) {
      scope.cancel();
    }
    _pruneScheduleImports();
    _writeRefreshes.clear();
    _readScheduler.close();
    _cancelDeferredRecovery();
    _lifecycleEpoch++;
    _ygdkGeneration++;
    _writeCoordinator.removeListener(_notify);
    _writeCoordinator.dispose();
    _ygdkReadbackState = const YgdkReadbackState.empty();
    _snapshots[FeatureId.ygdk] = const FeatureSnapshot(feature: FeatureId.ygdk);
    unawaited(_disposeBackendOnce(_backend).catchError((_) {}));
    super.dispose();
  }
}

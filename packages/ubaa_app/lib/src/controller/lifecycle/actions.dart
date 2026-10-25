import 'dart:async';
import '../../backend/unavailable.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/interactive_auth.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/lifecycle.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import 'package:ubaa_app/src/contracts/routing.dart';
import 'package:ubaa_app/src/contracts/write.dart';
import 'package:ubaa_app/src/write/cgyy_validation.dart';
import 'package:ubaa_app/src/write/ygdk_validation.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase, SessionRecoveryStatus;
import '../write/cgyy_readback.dart' show controllerVerifyCgyyCancellation;
import '../write/evaluation_readback.dart'
    show
        controllerNormalizeEvaluationTarget,
        controllerRefreshEvaluationAfterWrite;
import '../write/ygdk_readback.dart' show controllerRefreshYgdkAfterWrite;

mixin ControllerActions on ControllerState {
  Future<CacheUsageSummary> cacheUsage({required String accountId}) =>
      internalReadCacheUsage(accountId);

  Future<CacheClearOutcome> clearBusinessCache({required String accountId}) =>
      internalClearControllerCache(accountId);

  SessionRecoveryStatus recoveryStatusFor(FeatureId feature) =>
      internalFeatureRecoveryStates[feature] ?? SessionRecoveryStatus.idle;

  Future<void> refreshWriteReadbacks() =>
      internalLoadWriteReadbacks(force: true);

  Future<void> dismissWriteReadback(String id) =>
      internalDismissControllerReadback(id);

  /// 宿主在首页首帧之后调用；旧自动登录选项不参与是否开始检查的判断。
  void onHomeFirstFrame() {
    if (internalHomeFrameReported ||
        !internalUsesLocalRecovery ||
        internalPhase != AppPhase.home)
      return;
    internalHomeFrameReported = true;
    if (internalSessionRecoveryStatus == SessionRecoveryStatus.idle) {
      unawaited(recoverSession());
    }
  }

  Future<void> recoverSession({
    FeatureId feature = FeatureId.schedule,
    bool refreshHomeAfter = true,
  }) => internalRecoverSession(
    feature: feature,
    refreshHomeAfter: refreshHomeAfter,
  );

  /// 生命周期只更新可见状态；后台不开始未发送的恢复或首页同步。
  void setAppForeground(bool foreground) {
    internalAppForeground = foreground;
    if (!foreground) {
      internalCancelLoginVerification();
      internalLockDisplay?.cancel();
    }
    if (foreground) internalDrainDeferredRecovery();
    internalSyncRecoveryRetries();
    internalPumpReadTasks();
  }

  /// 本地网络变化只是唤醒提示，成功与否仍由原会话检查判断。
  void onNetworkChanged() => internalWakeNetworkRecovery();

  /// 返回前台复用当前实例；旧宿主已认证首页也转入同一恢复协调路径。
  Future<void> resumeSession() {
    if (internalDisposed ||
        internalPhase != AppPhase.home ||
        internalIsSigningOut)
      return Future<void>.value();
    if (!internalUsesLocalRecovery) {
      internalUsesLocalRecovery = true;
      internalSessionRecoveryStatus = SessionRecoveryStatus.ready;
    }
    return internalRecoverSession();
  }

  Future<void> saveScheduleSemester(String term) =>
      internalSaveScheduleSemester(term);

  void cancelScheduleImport(String term) => internalCancelScheduleImport(term);

  void setCaptchaAnswer(ConnectionMode route, String answer) =>
      internalSetCaptchaAnswer(route, answer);

  Future<void> refreshCaptcha(ConnectionMode route) =>
      internalRefreshCaptcha(route);

  Future<void> continueReadyLogin(ConnectionMode route) =>
      internalContinueReadyLogin(route);

  Future<void> continueWithFixedReadyRoute(ConnectionMode route) =>
      internalContinueReadyLogin(route, pinRoute: true);

  void cancelLoginVerification() => internalCancelLoginVerification();

  /// 只导出本次运行允许字段，不读取凭据、业务输入或磁盘会话。
  String exportDiagnostics() => internalDiagnostics.exportText();

  Future<void> initialize() => internalInitializeController();

  /// 在 Dart isolate 或宿主生命周期重建后替换 opaque backend。
  ///
  /// 新 backend 成功创建后才 dispose 旧 backend；随后重新读取 Core 的路线和
  ///认证状态。没有提供工厂、正在登录/重建或 controller 已销毁时返回 `false`，
  ///不伪造恢复成功。
  Future<bool> rebuildBackend() async {
    final factory = internalBackendFactory;
    if (factory == null ||
        internalDisposed ||
        internalRebuildingBackend ||
        isLoggingIn ||
        internalSessionRecoveryFuture != null ||
        internalWriteTransitions != 0 ||
        internalWriteCoordinator.hasPendingOperation)
      return false;
    // 初始化正在读取旧 backend 的认证/路线状态时，生命周期重建会与旧
    // handle 竞争并可能把结果写入新实例；等待初始化完成后再由下一次
    // resumed 事件触发重建。
    if (internalPhase == AppPhase.loggingIn ||
        internalPhase == AppPhase.checkingSession) {
      return false;
    }
    final previousLoginError = internalPhase == AppPhase.login
        ? internalError
        : null;
    final errorRevision = internalLoginFormRevision;
    final completion = Completer<void>();
    internalBackendRebuildCompletion = completion;
    internalCancelLoginVerification(notify: false);
    internalReleaseLoginSecret();
    internalSessionLifecycle.beginRebuild();
    internalBeginWriteTransition();
    internalSetPhase(AppPhase.checkingSession);
    try {
      final replacement = await factory();
      if (replacement is UnavailableBackend) {
        throw InitializationException(replacement.failure);
      }
      if (identical(replacement, internalBackend)) {
        internalError = UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
        internalSetPhase(AppPhase.login);
        return false;
      }
      final previous = internalBackend;
      try {
        await internalDisposeBackendOnce(previous);
      } on Object catch (error, stackTrace) {
        // 新实例已经创建；旧实例清理失败不能让新实例继续持有旧状态。
        internalRecordFailure(
          error,
          DiagnosticOperation.disposal,
          stackTrace: stackTrace,
        );
      }
      if (internalDisposed) {
        try {
          await internalDisposeBackendOnce(replacement);
        } on Object {
          // controller 已销毁时尽力释放新实例，不能向 UI 抛出异常。
        }
        return false;
      }
      internalSessionLifecycle.replaceBackend(replacement);
      internalReplaceWriteCoordinator(replacement);
      internalInitialized = false;
      internalUser = null;
      internalActiveRoutes = const <ConnectionMode>[];
      internalResetFeatureSnapshots();
      internalSessionLifecycle.endRebuild();
      await internalInitializeController(
        previousLoginError: internalLoginFormRevision == errorRevision
            ? previousLoginError
            : null,
      );
      return true;
    } on BackendException catch (exception, stackTrace) {
      internalError = internalRecordFailure(
        exception,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
      internalSetPhase(AppPhase.login);
      return false;
    } on Object catch (error, stackTrace) {
      internalError = internalRecordFailure(
        error,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
      internalSetPhase(AppPhase.login);
      return false;
    } finally {
      internalEndWriteTransition();
      internalBackendRebuildCompletion = null;
      completion.complete();
      internalSessionLifecycle.endRebuild();
      internalNotify();
    }
  }

  void setUsername(String value) {
    if (internalDisposed || isLoggingIn || internalIsSigningOut) return;
    final accountChanged = value.trim() != internalLoginForm.username.trim();
    if (accountChanged)
      internalCancelLoginVerification(releasePassword: false, notify: false);
    if (accountChanged) internalManualAuthenticationRequired = true;
    internalLoginFormRevision++;
    internalLoginCredentialRevision++;
    internalLoginForm = internalLoginForm.copyWith(
      username: value,
      password: accountChanged ? '' : null,
      captcha: accountChanged ? '' : null,
    );
    internalError = null;
    internalNotify();
  }

  void setPassword(String value) {
    if (internalDisposed || isLoggingIn || internalIsSigningOut) return;
    if (value != internalLoginForm.password)
      internalCancelLoginVerification(releasePassword: false, notify: false);
    internalLoginFormRevision++;
    internalLoginCredentialRevision++;
    internalLoginForm = internalLoginForm.copyWith(password: value);
    internalError = null;
    internalNotify();
  }

  void setCaptcha(String value) {
    if (internalDisposed || isLoggingIn || internalIsSigningOut) return;
    internalLoginFormRevision++;
    internalLoginCredentialRevision++;
    internalLoginForm = internalLoginForm.copyWith(captcha: value);
    internalError = null;
    internalNotify();
  }

  void setRememberPassword(bool value) {
    if (!internalCanEditLoginOptions) return;
    internalLoginFormRevision++;
    internalLoginForm = internalLoginForm.copyWith(
      rememberPassword: value,
      autoLogin: value ? internalLoginForm.autoLogin : false,
    );
    internalNotify();
  }

  void setAutoLogin(bool value) {
    if (!internalCanEditLoginOptions) return;
    internalLoginFormRevision++;
    internalLoginForm = internalLoginForm.copyWith(
      autoLogin: value,
      rememberPassword: value ? true : internalLoginForm.rememberPassword,
    );
    internalNotify();
  }

  Future<void> setRoutePolicy(RoutePolicy value) =>
      internalSetRoutePolicyController(value);

  Future<void> submitLogin({bool preserveHome = false}) {
    if (internalBackend case final InteractiveLoginBackend backend) {
      if (internalDisposed ||
          internalIsSigningOut ||
          internalRebuildingBackend ||
          internalSessionRecoveryFuture != null ||
          internalWriteCoordinator.hasPendingOperation ||
          internalWriteTransitions != 0)
        return Future.value();
      if (!internalInteractiveEngaged)
        internalInteractiveInPlace =
            preserveHome && internalPhase == AppPhase.home;
      return internalSubmitInteractiveLogin(backend);
    }
    return internalSubmitLoginController(preserveHome: preserveHome);
  }

  /// 用户明确请求学期选项，不占用全局课表快照。
  Future<FeatureResult> loadAcademicTerms({bool forceRefresh = false}) =>
      internalLocalFirstOptions(
        const FeatureQuery(view: FeatureQueryView.scheduleTerms),
        forceRefresh,
        () => internalLoadAcademicTerms(forceRefresh: forceRefresh),
      );

  /// 教学周选项按原学期独立读取，不覆盖当前课表或查询草稿。
  Future<FeatureResult> loadAcademicWeeks(
    String term, {
    bool forceRefresh = false,
  }) => internalLocalFirstOptions(
    FeatureQuery(view: FeatureQueryView.scheduleWeeks, term: term),
    forceRefresh,
    () => internalLoadAcademicWeeks(term, forceRefresh: forceRefresh),
  );

  /// 活动类型独立读取，不覆盖研讨室日时段和已选目标。
  Future<FeatureResult> loadCgyyPurposes({bool forceRefresh = false}) =>
      internalLocalFirstOptions(
        const FeatureQuery(view: FeatureQueryView.cgyyPurposeTypes),
        forceRefresh,
        () => internalLoadCgyyPurposes(forceRefresh: forceRefresh),
        feature: FeatureId.cgyy,
      );

  /// 成绩统计的独立读取，不改变当前页面的查询或详情帧。
  Future<FeatureResult> loadGradeTerm(
    String term, {
    bool forceRefresh = false,
  }) => internalLoadGradeTerm(term, forceRefresh: forceRefresh);

  Future<GradesAggregate> loadAllGrades({
    bool forceRefresh = false,
    void Function(GradesAggregate)? onProgress,
  }) => internalLoadGradesWithCache(
    forceRefresh: forceRefresh,
    onProgress: onProgress,
  );

  /// 首页变化检查只读取唯一标为当前的学期；缺失时不猜第一项。
  Future<GradeTermRead?> loadCurrentGrades({
    bool forceRefresh = false,
    bool background = false,
  }) => internalLoadCurrentGrades(
    forceRefresh: forceRefresh,
    priority: background ? ReadPriority.background : ReadPriority.interactive,
  );

  Future<FeatureResult> loadHomeDaySchedule(
    String date, {
    bool forceRefresh = false,
  }) => internalLoadHomeDaySchedule(date, forceRefresh: forceRefresh);

  Future<FeatureResult> loadHomeSupplement(
    HomeSupplement source, {
    bool forceRefresh = false,
  }) => internalLoadHomeSupplement(source, forceRefresh: forceRefresh);

  Future<void> refreshHome({Iterable<FeatureId>? only}) =>
      internalRefreshHome(only: only);

  Future<void> retryFeature(FeatureId feature) {
    final query = internalSnapshots[feature]?.readContext?.query;
    return query == null
        ? refreshHome(only: <FeatureId>[feature])
        : refreshFeatureQuery(feature, query);
  }

  /// 对支持 [FeatureQueryBackend] 的生产实现执行单领域筛选读取。
  Future<void> refreshFeatureQuery(FeatureId feature, FeatureQuery query) =>
      internalRefreshFeatureQuery(feature, query);

  /// 准备博雅选课/退选的 typed 一次性意图；准备本身不提交写请求。
  Future<WriteIntent> prepareBykcWrite(
    WriteOperation operation,
    int courseId,
  ) async {
    final backend = internalBackend;
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
    final backend = internalBackend;
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
    final backend = internalBackend;
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
    final backend = internalBackend;
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
    final backend = internalBackend;
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
    final backend = internalBackend;
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
    final backend = internalBackend;
    if (backend is! YgdkWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    return (backend as YgdkWriteBackend).prepareYgdkSubmit(
      validateYgdkSubmitInput(input),
    );
  }

  /// 准备研讨室预约写意图；只接受 Core 已核对的 typed actions。
  Future<WriteIntent> prepareCgyySubmitWrite(CgyySubmitInput input) async {
    final backend = internalBackend;
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
    final backend = internalBackend;
    if (backend is! EvaluationWriteBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final normalized = targets
        .map(controllerNormalizeEvaluationTarget)
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
      internalCommitWriteWithBackend(internalBackend, intentId);

  /// 释放尚未确认的一次性意图；该操作不提交任何上游写请求。
  Future<void> discardWriteIntent(String intentId) =>
      internalDiscardWriteWithBackend(internalBackend, intentId);

  /// 写入成功后仅刷新关联只读领域，用于结果核对；不会重试写请求。
  Future<void> refreshAfterWrite(
    WriteOperation operation, [
    FeatureQuery? readbackQuery,
  ]) => internalRefreshAfterWrite(operation, readbackQuery);

  /// 在场馆订单刷新完成后，仅按公开订单编号匹配提交收据。
  ///
  /// 该方法不发起额外请求，调用方必须先等待 [refreshAfterWrite]；读取失败、
  /// 空结果或不匹配均返回 `false`，绝不把写入结果升级为已核对。
  Future<bool> matchesCgyyReceipt(CgyyReservationReceipt receipt) async {
    if (receipt.orderId <= 0) return false;
    final snapshot = internalSnapshots[FeatureId.cgyy];
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
  }) => controllerVerifyCgyyCancellation(
    this,
    orderId: orderId,
    expectedRoute: expectedRoute,
  );

  /// 在 intent 的实际路线 best-effort 刷新阳光打卡概览与首页记录。
  ///
  /// 冻结来源没有提供记录与本次写入的严格关联规则，因此该方法不
  /// 接收收据也不返回核对结论，更不得将 OutcomeUnknown 升级为成功。
  Future<void> refreshYgdkAfterWrite({required ConnectionMode expectedRoute}) =>
      controllerRefreshYgdkAfterWrite(this, expectedRoute: expectedRoute);

  /// 在 intent 的实际路线 best-effort 刷新评教课程。
  ///
  /// 该回读只更新 Evaluation 快照，不改写结果，也不会重试提交。
  Future<void> refreshEvaluationAfterWrite({
    required ConnectionMode expectedRoute,
  }) =>
      controllerRefreshEvaluationAfterWrite(this, expectedRoute: expectedRoute);

  Future<void> logout({
    bool clearSavedCredential = false,
    Future<void> Function()? clearLocalData,
  }) => internalLogoutController(
    clearSavedCredential: clearSavedCredential,
    clearLocalData: clearLocalData,
  );

  Future<void> setTelemetryEnabled(bool value) =>
      internalSetTelemetryEnabledController(value);

  Future<void> clearTelemetryQueue() async {
    await internalFlushTelemetry();
  }

  void clearError() {
    internalClearError();
  }

  @internal
  void internalClearError() {
    if (internalError == null) return;
    internalError = null;
    internalNotify();
  }

  @internal
  bool internalRoutePolicyHasSession(
    RoutePolicy policy,
    List<ConnectionMode> activeRoutes,
  ) => switch (policy) {
    RoutePolicy.auto => activeRoutes.isNotEmpty,
    RoutePolicy.direct => activeRoutes.contains(ConnectionMode.direct),
    RoutePolicy.webvpn => activeRoutes.contains(ConnectionMode.webvpn),
  };

  @internal
  void internalApplyRouteSettings(BackendRouteSettings settings) {
    internalActiveRoutes = List<ConnectionMode>.unmodifiable(
      settings.activeRoutes,
    );
    internalLoginForm = internalLoginForm.copyWith(
      routePolicy: settings.defaultPolicy,
    );
  }

  @internal
  Future<void> internalRefreshRouteSettings() async {
    final scope = internalCaptureSessionScope();
    if (scope.backend case final RouteSettingsBackend routeBackend) {
      try {
        final settings = await routeBackend.routeSettings();
        if (!scope.isCurrent) return;
        internalApplyRouteSettings(settings);
      } on Object catch (error, stackTrace) {
        if (!scope.isCurrent) return;
        // 登录已经成功时，路线状态读取失败不能把账号重新置为失败；清空
        // 不确定的活动槽位，后续读取仍由 Core 返回实际错误。
        internalActiveRoutes = const <ConnectionMode>[];
        internalRecordFailure(
          error,
          DiagnosticOperation.routeChange,
          stackTrace: stackTrace,
        );
      }
    }
  }

  @internal
  void internalSetPhase(AppPhase phase) {
    if (phase == AppPhase.login) {
      internalCacheLifecycle.invalidateReads();
      internalSessionLifecycle.invalidate();
      internalYgdkGeneration++;
      internalWriteCoordinator.invalidate();
    }
    internalPhase = phase;
    internalNotify();
  }

  @internal
  void internalNotify() {
    internalLockDisplay?.validate();
    internalSyncRecoveryRetries();
    internalDrainDeferredRecovery();
    internalPumpReadTasks();
    if (!internalDisposed) notifyListeners();
  }

  @internal
  Future<void> internalDisposeBackendOnce(UbaaBackend backend) {
    final existing = internalBackendDisposals[backend];
    if (existing != null) return existing;
    if (backend is! BackendLifecycle) return Future<void>.value();
    final lifecycle = backend as BackendLifecycle;

    final completer = Completer<void>();
    internalBackendDisposals[backend] = completer.future;
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
    if (internalDisposed) return;
    internalCancelLoginVerification(notify: false);
    // 密码释放属于销毁操作，不能等待已撤销的登录任务迟到收尾。
    internalReleaseLoginSecret();
    internalInPlaceLogin = false;
    internalInteractiveInPlace = false;
    internalLockDisplay?.cancel();
    internalSessionLifecycle.dispose();
    for (final scope in internalReadScopes.toList()) {
      scope.cancel();
    }
    internalPruneScheduleImports();
    internalWriteRefreshes.clear();
    internalReadScheduler.close();
    internalCancelDeferredRecovery();
    internalSessionLifecycle.invalidate();
    internalYgdkGeneration++;
    internalWriteCoordinator.removeListener(internalNotify);
    internalWriteCoordinator.dispose();
    internalYgdkReadbackState = const YgdkReadbackState.empty();
    internalSnapshots[FeatureId.ygdk] = const FeatureSnapshot(
      feature: FeatureId.ygdk,
    );
    unawaited(internalDisposeBackendOnce(internalBackend).catchError((_) {}));
    super.dispose();
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/interactive_auth.dart';
import 'package:ubaa_app/src/contracts/progressive.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import 'package:ubaa_app/src/contracts/routing.dart';
import 'package:ubaa_app/src/contracts/recovery.dart';
import 'package:ubaa_app/src/contracts/write.dart';
import 'package:ubaa_app/src/write/coordinator.dart';
import 'models.dart' show ProgressiveScope, RecoveryRequest;
import 'types.dart' show AppPhase, SessionRecoveryStatus;

abstract class ControllerOperations extends ChangeNotifier {
  Future<CacheUsageSummary> cacheUsage({required String accountId});
  Future<CacheClearOutcome> clearBusinessCache({required String accountId});
  SessionRecoveryStatus recoveryStatusFor(FeatureId feature);

  Future<void> recoverSession({
    FeatureId feature = FeatureId.schedule,
    bool refreshHomeAfter = true,
  });

  /// 首页变化检查只读取唯一标为当前的学期；缺失时不猜第一项。
  Future<GradeTermRead?> loadCurrentGrades({
    bool forceRefresh = false,
    bool background = false,
  });

  Future<void> refreshHome({Iterable<FeatureId>? only});

  /// 对支持 [FeatureQueryBackend] 的生产实现执行单领域筛选读取。
  Future<void> refreshFeatureQuery(FeatureId feature, FeatureQuery query);

  /// 提交已确认的一次性意图；不接受任意请求正文，也不自动重试。
  Future<WriteCommitResult> commitWrite(String intentId);

  /// 释放尚未确认的一次性意图；该操作不提交任何上游写请求。
  Future<void> discardWriteIntent(String intentId);

  /// 写入成功后仅刷新关联只读领域，用于结果核对；不会重试写请求。
  Future<void> refreshAfterWrite(
    WriteOperation operation, [
    FeatureQuery? readbackQuery,
  ]);

  /// 在场馆订单刷新完成后，仅按公开订单编号匹配提交收据。
  ///
  /// 该方法不发起额外请求，调用方必须先等待 [refreshAfterWrite]；读取失败、
  /// 空结果或不匹配均返回 `false`，绝不把写入结果升级为已核对。
  Future<bool> matchesCgyyReceipt(CgyyReservationReceipt receipt);

  /// 在 intent 的实际路线上执行场馆取消列表+详情双回读。
  Future<bool> verifyCgyyCancellation({
    required int orderId,
    required ConnectionMode expectedRoute,
  });

  /// 在 intent 的实际路线 best-effort 刷新阳光打卡概览与首页记录。
  ///
  /// 冻结来源没有提供记录与本次写入的严格关联规则，因此该方法不
  /// 接收收据也不返回核对结论，更不得将 OutcomeUnknown 升级为成功。
  Future<void> refreshYgdkAfterWrite({required ConnectionMode expectedRoute});

  /// 在 intent 的实际路线 best-effort 刷新评教课程。
  ///
  /// 该回读只更新 Evaluation 快照，不改写结果，也不会重试提交。
  Future<void> refreshEvaluationAfterWrite({
    required ConnectionMode expectedRoute,
  });
  Future<void> logout({
    bool clearSavedCredential = false,
    Future<void> Function()? clearLocalData,
  });

  void clearError();
  @internal
  void internalClearError();
  @internal
  bool internalRoutePolicyHasSession(
    RoutePolicy policy,
    List<ConnectionMode> activeRoutes,
  );
  @internal
  void internalApplyRouteSettings(BackendRouteSettings settings);
  @internal
  Future<void> internalRefreshRouteSettings();
  @internal
  void internalSetPhase(AppPhase phase);
  @internal
  void internalNotify();
  @internal
  Future<void> internalDisposeBackendOnce(UbaaBackend backend);
  @internal
  Future<CgyyLockDisplaySession> internalOpenLockDisplay();
  @internal
  Future<void> internalRefreshHome({
    Iterable<FeatureId>? only,
    bool writeReadback = false,
  });
  @internal
  /// 对支持 [FeatureQueryBackend] 的生产实现执行单领域筛选读取。
  ///
  /// 不支持查询的 fake backend 明确报 unsupported，不会在 Dart 端拼接请求。
  Future<void> internalRefreshFeatureQuery(
    FeatureId feature,
    FeatureQuery query, {
    bool writeReadback = false,
  });
  @internal
  FeatureReadContext internalBeginFeatureRead(
    FeatureId feature,
    int generation,
    FeatureQuery? query,
  );
  @internal
  int internalNextFeatureGeneration(FeatureId feature);

  @internal
  bool internalApplyFeatureResultIfCurrent(
    FeatureId feature,
    FeatureResult result,
    int generation,
    int lifecycleEpoch, {
    int? ygdkGeneration,
    FeatureReadContext? readContext,
    bool preservePreviousOnFailure = false,
  });
  @internal
  bool internalIsFeatureLoadCurrent(
    FeatureId feature,
    int generation,
    int lifecycleEpoch,
    int? ygdkGeneration,
  );
  @internal
  void internalResetFeatureSnapshots({bool advanceLifecycle = true});
  @internal
  Future<void>? internalPendingFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  );
  @internal
  Future<FeatureResult> internalScheduleAuxiliaryRead(
    UbaaBackend backend,
    FeatureId feature,
    ReadPriority priority,
    bool Function() current,
    Future<FeatureResult> Function() operation, {
    ReadDemand? demand,
  });
  @internal
  bool internalCanRunScheduledRead(ReadPriority priority);
  @internal
  void internalPumpReadTasks();
  @internal
  void internalCancelSegmentedReadScopes(FeatureId feature);
  @internal
  Future<FeatureResult> internalReadScheduledFeature(
    FeatureId feature,
    FeatureQuery? query,
    ProgressiveScope scope, {
    required bool writeReadback,
    required void Function(FeatureReadBatch) onBatch,
  });
  @internal
  void internalPruneScheduleImports();
  @internal
  Future<void> internalSaveScheduleSemester(String term);
  @internal
  void internalCancelScheduleImport(String term);

  @internal
  String? get internalScheduleWidgetOwner;
  @internal
  Object get internalScheduleWidgetRevision;
  @internal
  Future<ScheduleWidgetSnapshot> internalReadScheduleWidgets(
    bool Function() publisherCurrent,
  );
  @internal
  bool get internalHasScheduledTargetRecovery;
  @internal
  bool get internalLegacyReadSessionBlocked;
  @internal
  bool get internalReadTransitionBlocked;

  @internal
  Future<void> internalScheduleReadAuthentication(
    FeatureId feature,
    ReadPriority priority,
    bool Function() current, {
    bool force = false,
    ReadDemand? demand,
  });
  @internal
  Future<T> internalScheduledRead<T>(
    FeatureId feature,
    ReadPriority priority,
    bool Function() current,
    Future<T> Function() operation, {
    void Function(T)? discard,
    bool writeReadback = false,
    ReadDemand? demand,
  });
  @internal
  void internalInvalidateReadPlansAfterLogin(RecoveryRequest request);
  @internal
  Future<void> internalRefreshAfterWrite(
    WriteOperation operation, [
    FeatureQuery? readbackQuery,
  ]);
  @internal
  Future<FeatureResult> internalLoadAcademicTerms({
    required bool forceRefresh,
    ReadPriority priority = ReadPriority.interactive,
  });

  @internal
  FeatureResult internalAcademicTermsConflict();

  @internal
  Future<FeatureResult> internalLoadAcademicWeeks(
    String term, {
    required bool forceRefresh,
  });

  @internal
  Future<FeatureResult> internalLoadCgyyPurposes({required bool forceRefresh});

  @internal
  Future<FeatureResult> internalLoadHomeDaySchedule(
    String date, {
    required bool forceRefresh,
  });

  @internal
  Future<FeatureResult> internalLoadHomeSupplement(
    HomeSupplement source, {
    required bool forceRefresh,
  });

  @internal
  bool internalIsHomeDefaultCurrent(
    FeatureId feature,
    int generation,
    int lifecycle,
  );
  @internal
  void internalBeginHomeDefault(FeatureId feature, FeatureReadContext context);
  @internal
  void internalAcceptHomeDefault(
    FeatureId feature,
    FeatureResult result,
    FeatureReadContext? context,
  );
  @internal
  Future<FeatureResult>? internalReadSharedGradeQuery(FeatureQuery query);
  @internal
  Future<GradeTermRead?> internalLoadCurrentGrades({
    required bool forceRefresh,
    required ReadPriority priority,
  });
  @internal
  void internalRememberGradeResult(
    FeatureResult result,
    FeatureQuery? query, {
    bool fresh = true,
  });
  @internal
  FeatureResult? internalCachedGradeQuery(FeatureQuery query);

  @internal
  Future<FeatureResult> internalLoadGradeTerm(
    String term, {
    required bool forceRefresh,
  });

  @internal
  Future<GradesAggregate> internalLoadAllGrades({required bool forceRefresh});

  @internal
  WriteCoordinator internalCreateWriteCoordinator(UbaaBackend backend);
  @internal
  void internalBeginWriteTransition();
  @internal
  void internalEndWriteTransition();
  @internal
  void internalReplaceWriteCoordinator(UbaaBackend backend);
  @internal
  Future<WriteCommitResult> internalCommitWriteWithBackend(
    UbaaBackend backend,
    String intentId,
  );
  @internal
  Future<void> internalDiscardWriteWithBackend(
    UbaaBackend backend,
    String intentId,
  );
  @internal
  Future<WriteCommitResult> internalCommitWithAccountCache(
    CacheWriteBackend backend,
    String intentId,
    String accountId,
  );

  @internal
  void internalDrainWriteRefreshes();

  @internal
  Future<void> internalLoadWriteReadbacks({bool force = false});
  @internal
  Future<void> internalDismissControllerReadback(String id);
  @internal
  void internalClearWriteReadbacks();
  @internal
  UiError internalRecordFailure(
    Object cause,
    DiagnosticOperation operation, {
    StackTrace? stackTrace,
    FeatureId? feature,
    Duration? latency,
  });
  @internal
  Future<void> internalRecordAppOpen();
  @internal
  Future<void> internalRecordFeature(
    FeatureId feature, {
    bool success = false,
    bool empty = false,
    UiError? error,
    Duration? latency,
  });

  @internal
  Future<void> internalFlushTelemetry();

  @internal
  Future<bool> internalInitializeLocalHome();
  @internal
  Future<void> internalRecoverSession({
    FeatureId feature = FeatureId.schedule,
    bool refreshHomeAfter = true,
  });
  @internal
  bool internalRecoveryIsCurrent(int epoch);
  @internal
  Future<void> internalPerformSessionRecovery(
    RecoveryRequest request, {
    bool allowRebuild = true,
  });
  @internal
  Future<void> internalRequireReadSession({FeatureId? feature});
  @internal
  Future<void> internalRetainCurrentAccount({
    required String username,
    required bool retainSession,
  });
  @internal
  Future<void> internalRestoreCachedHome(LocalAccount account);

  @internal
  Future<void> internalCloseOfflineAccount({bool remove = false});
  @internal
  Future<void> internalRejectMismatchedAccount();
  @internal
  Future<void> internalLogoutController({
    required bool clearSavedCredential,
    Future<void> Function()? clearLocalData,
  });

  @internal
  Future<CacheUsageSummary> internalReadCacheUsage(String accountId);
  @internal
  Future<CacheClearOutcome> internalClearControllerCache(String accountId);

  @internal
  Future<void> internalRestoreCachedProfile(
    UbaaBackend backend,
    LocalAccount account,
    int epoch,
  );
  @internal
  Future<void> internalQueueProfileRefresh({bool force = false});

  @internal
  Future<void> internalRestoreCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    int generation,
    int lifecycle,
    int? ygdkGeneration,
  );
  @internal
  Future<FeatureResult> internalLocalFirstOptions(
    FeatureQuery query,
    bool forceRefresh,
    Future<FeatureResult> Function() read, {
    FeatureId feature = FeatureId.schedule,
  });
  @internal
  Future<GradesAggregate> internalLoadGradesWithCache({
    required bool forceRefresh,
    void Function(GradesAggregate)? onProgress,
  });

  @internal
  bool get internalRecoveryMustWait;
  @internal
  void internalCancelDeferredRecovery();
  @internal
  void internalDrainDeferredRecovery();
  @internal
  void internalStartNextRecovery();
  @internal
  Future<bool> internalRebuildDuringRecovery(RecoveryRequest request);

  @internal
  void internalClearRecoveryRetries();
  @internal
  void internalFinishRecoveryRetry(RecoveryRequest request);
  @internal
  void internalSyncRecoveryRetries();
  @internal
  void internalWakeNetworkRecovery();
  @internal
  void internalClearBusinessRetries();
  @internal
  void internalBeginBusinessAttempt(
    FeatureId feature,
    FeatureQuery? query,
    int revision,
  );
  @internal
  void internalFinishBusinessAttempt(
    FeatureId feature,
    FeatureQuery? query,
    int revision,
    int epoch,
    UiError? error,
  );

  @internal
  void internalSyncBusinessRetries();

  @internal
  Future<UserSummary?> internalRecoverRequiredProfile(
    RequiredSessionBackend backend,
    FeatureId feature,
    int epoch,
  );
  @internal
  Future<UserSummary?> internalRecoverLegacyProfile(int epoch);
  @internal
  bool get internalCanEditLoginOptions;

  @internal
  void internalReleaseLoginSecret();
  @internal
  Future<void> internalInitializeController({UiError? previousLoginError});

  @internal
  Future<void> internalSubmitLoginController({bool preserveHome = false});
  @internal
  Future<void> internalCompleteAuthenticatedLogin(
    LoginInput input,
    UserSummary? profile,
    int epoch,
  );
  @internal
  Future<void> internalMutateCredential(
    int epoch,
    Future<void> Function() action,
  );
  @internal
  Future<void> internalSetRoutePolicyController(RoutePolicy value);
  @internal
  Future<void> internalSetTelemetryEnabledController(bool value);

  @internal
  Future<void> internalSubmitInteractiveLogin(InteractiveLoginBackend backend);

  @internal
  void internalSetCaptchaAnswer(ConnectionMode route, String answer);

  @internal
  Future<void> internalRefreshCaptcha(ConnectionMode route);
  @internal
  Future<void> internalContinueReadyLogin(
    ConnectionMode route, {
    bool pinRoute = false,
  });

  @internal
  void internalCancelLoginVerification({
    bool releasePassword = true,
    bool notify = true,
  });
}

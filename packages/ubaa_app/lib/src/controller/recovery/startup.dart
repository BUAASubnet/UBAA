import '../../contracts/app_service.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/lifecycle.dart';
import 'package:ubaa_app/src/contracts/profile.dart';
import 'package:ubaa_app/src/contracts/routing.dart';
import 'package:ubaa_app/src/contracts/recovery.dart';
import '../../contracts/session_recovery.dart';
import 'retry.dart' show controllerTemporaryRecoveryFailure;
import '../state/recovery_result.dart';
import '../state/models.dart' show RecoveryRequest;
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase, SessionRecoveryStatus;

mixin ControllerOfflineStartup on ControllerState {
  @internal
  Future<bool> internalInitializeLocalHome() async {
    final epoch = internalLifecycleEpoch;
    final formRevision = internalLoginFormRevision;
    final store = internalLocalAccountStore!;
    internalSetPhase(AppPhase.checkingSession);
    try {
      var index = await store.read();
      if (internalDisposed || epoch != internalLifecycleEpoch) return true;
      if (index == null) {
        // 一次性迁移只建立本机索引，不因升级启用旧密码的自动提交。
        final saved = await internalCredentialVault.read();
        if (internalDisposed || epoch != internalLifecycleEpoch) return true;
        if (saved != null && saved.isUsable) {
          index = await store.retain(saved.username, retainSession: true);
        }
      }
      if (internalDisposed || epoch != internalLifecycleEpoch) return true;
      if (index == null) return false;
      if (!index.canRestore || index.account == null) {
        internalSessionRecoveryStatus = SessionRecoveryStatus.signedOut;
        internalSetPhase(AppPhase.login);
        return true;
      }
      // 路线是本机配置；缓存首屏也必须沿已保存路线读取，不能先按 Auto 混用来源。
      if (internalBackend case final RouteSettingsBackend settings) {
        final routes = await settings.routeSettings();
        if (internalDisposed || epoch != internalLifecycleEpoch) return true;
        internalApplyRouteSettings(routes);
      }
      if (store is SecureLocalAccountStore) {
        final shared = await store.capture();
        if (shared == null ||
            shared.state.generation != index.generation ||
            internalDisposed ||
            epoch != internalLifecycleEpoch) {
          throw const RecoveryInterrupted(RecoveryStopReason.superseded);
        }
        internalSharedAccountSnapshot = shared;
        if (internalBackend case final SharedAccountBackend backend) {
          await backend.bindSharedAccount(await store.bindSnapshot(shared));
        }
      }
      Credential? saved;
      if (internalCredentialRestoreAllowed &&
          internalLoginFormRevision == 0 &&
          internalCredentialVault.isAvailable) {
        try {
          saved = await internalCredentialVault.read();
        } on Object catch (error, stackTrace) {
          if (internalDisposed || epoch != internalLifecycleEpoch) return true;
          internalRecordFailure(
            error,
            DiagnosticOperation.initialization,
            stackTrace: stackTrace,
          );
        }
      }
      if (internalDisposed || epoch != internalLifecycleEpoch) return true;
      if (internalNeedsManualLogin(formRevision)) return true;
      final restoresOptions =
          saved != null &&
          saved.isUsable &&
          saved.username.trim() == index.account!.username;
      internalLocalAccount = index.account;
      internalUser = UserSummary(username: index.account!.username);
      internalLoginForm = internalLoginForm.copyWith(
        username: index.account!.username,
        // 首页只保留登录选项，重新认证不会因默认值而删除已保存凭据。
        rememberPassword: restoresOptions ? true : null,
        autoLogin: restoresOptions ? saved.autoLogin : null,
      );
      internalUsesLocalRecovery = true;
      internalSessionRecoveryStatus = SessionRecoveryStatus.idle;
      // 先登记本地打开任务，状态通知中的详情读取也能等待同一账号句柄。
      // 限时等待本机首页缓存，首帧直接显示缓存内容而不是加载动画；
      // 磁盘或密钥读取较慢时到时即进入首页，缓存稍后补上。
      final waited = Completer<void>();
      void release() {
        if (!waited.isCompleted) waited.complete();
      }

      final limit = Timer(const Duration(milliseconds: 800), release);
      unawaited(
        internalRestoreCachedHome(index.account!).whenComplete(release),
      );
      await waited.future;
      limit.cancel();
      if (internalDisposed || epoch != internalLifecycleEpoch) return true;
      internalSetPhase(AppPhase.home);
      // 预读期间尚未进入首页，待核实提示只在首页阶段读取；进入后补读。
      unawaited(internalLoadWriteReadbacks());
      if (internalHomeFrameReported) {
        // backend 在已展示首页后被显式替换时不会再产生新的首帧；仍须
        // 沿既有恢复任务重新核对继任实例的会话和身份。
        unawaited(internalAutomaticSchoolAction(internalRecoverSession));
      }
      return true;
    } on Object catch (error, stackTrace) {
      if (internalDisposed || epoch != internalLifecycleEpoch) return true;
      // 无法确认本机账号时不能授予离线首页入口；保留材料供手动登录恢复。
      // 已确认账号后的缓存正文故障由独立恢复任务处理，不受此分支影响。
      internalUsesLocalRecovery = false;
      internalLocalAccount = null;
      internalUser = null;
      internalSessionRecoveryStatus = SessionRecoveryStatus.needsLogin;
      internalError = internalRecordFailure(
        error,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
      internalSetPhase(AppPhase.login);
      return true;
    }
  }

  @internal
  Future<void> internalRecoverSession({
    FeatureId feature = FeatureId.schedule,
    bool refreshHomeAfter = true,
    bool forceConnectionCheck = false,
  }) {
    if (internalDisposed ||
        internalIsSigningOut ||
        internalClearingBusinessCache ||
        !internalUsesLocalRecovery ||
        internalPhase != AppPhase.home)
      return Future<void>.value();
    final active = internalActiveRecovery;
    if (active != null &&
        active.feature == feature &&
        !forceConnectionCheck &&
        (active.refreshHomeAfter || !refreshHomeAfter)) {
      active.refreshHomeAfter |= refreshHomeAfter;
      active.interactive |= !refreshHomeAfter;
      return active.completion.future;
    }
    final request = internalQueuedRecoveries.putIfAbsent(
      feature,
      () => RecoveryRequest(feature, internalLifecycleEpoch, refreshHomeAfter),
    );
    request.refreshHomeAfter |= refreshHomeAfter;
    request.interactive |= !refreshHomeAfter;
    internalStartNextRecovery();
    return request.completion.future;
  }

  @internal
  bool internalRecoveryIsCurrent(int epoch) =>
      !internalDisposed &&
      epoch == internalLifecycleEpoch &&
      internalPhase == AppPhase.home;

  /// 归属已经变化时不交付结果；其他终态由同一个入口发布。
  @internal
  Future<ControllerRecoveryResult?> internalPerformSessionRecovery(
    RecoveryRequest request, {
    bool allowRebuild = true,
  }) async {
    final epoch = request.epoch;
    var usesSharedRecovery = false;
    ControllerRecoveryResult result;
    try {
      if (request.refreshHomeAfter &&
          internalBackend is HomeRecoveryBatchBackend) {
        await (internalBackend as HomeRecoveryBatchBackend)
            .invalidateHomeRecoveryBatch();
        if (!internalRecoveryIsCurrent(epoch)) return null;
      }
      if (internalBackend case final RouteSettingsBackend settings) {
        final settingsResult = await settings.routeSettings();
        if (!internalRecoveryIsCurrent(epoch)) return null;
        internalApplyRouteSettings(settingsResult);
      }
      final backend = internalBackend;
      usesSharedRecovery =
          backend is RequiredSessionBackend &&
          internalLocalAccountStore is SecureLocalAccountStore;
      final profile = backend is RequiredSessionBackend
          ? await internalRecoverRequiredProfile(
              backend as RequiredSessionBackend,
              request.feature,
              epoch,
            )
          : await internalRecoverLegacyProfile(epoch);
      if (!internalRecoveryIsCurrent(epoch)) return null;
      if (profile == null) {
        result = const ControllerRecoveryStopped(
          SessionRecoveryStatus.needsLogin,
        );
      } else {
        final expected =
            internalLocalAccount?.username ?? internalUser?.username;
        if (expected != null &&
            profile.username != expected &&
            profile.schoolId != expected) {
          await internalRejectMismatchedAccount();
          return null;
        }
        final deliveryScope = backend is RequiredSessionBackend
            ? internalSharedRecoveryScope
            : null;
        await internalRefreshRouteSettings();
        result = ControllerRecoveredSession(profile, deliveryScope);
      }
      await _publishRecoveryResult(request, result);
      return result;
    } on Object catch (caughtError, caughtStackTrace) {
      Object error = caughtError;
      StackTrace stackTrace = caughtStackTrace;
      if (!internalRecoveryIsCurrent(epoch)) return null;
      if (error is RecoveryInterrupted || error is LocalAccountConflict) {
        result = ControllerRecoveryStopped(
          internalAutomaticCredentialBlocked
              ? SessionRecoveryStatus.needsLogin
              : SessionRecoveryStatus.idle,
        );
      } else {
        if (allowRebuild && error is BackendException && error.clientDisposed) {
          try {
            if (await internalRebuildDuringRecovery(request)) {
              return await internalPerformSessionRecovery(
                request,
                allowRebuild: false,
              );
            }
          } on Object catch (replacementError, replacementTrace) {
            error = replacementError;
            stackTrace = replacementTrace;
          }
          if (!internalRecoveryIsCurrent(request.epoch)) return null;
        }
        if (error is BackendException && error.accountMismatch) {
          await internalRejectMismatchedAccount();
          return null;
        }
        if (error is BackendException &&
            error.captchaRequired &&
            error.resolvedRoute != null) {
          final input = await internalApprovedRecoveryInput(request.epoch);
          if (!internalRecoveryIsCurrent(request.epoch)) return null;
          internalAutomaticCredentialBlocked = true;
          if (input != null) {
            result = ControllerRecoveryVerification(
              input,
              error.resolvedRoute!,
            );
            await _publishRecoveryResult(request, result);
            return result;
          }
        }
        if (error is BackendException &&
            (error.code == UbaaErrorCode.invalidCredentials ||
                error.code == UbaaErrorCode.upstreamChanged)) {
          internalAutomaticCredentialBlocked = true;
        }
        if (error is BackendException &&
            error.code == UbaaErrorCode.invalidCredentials &&
            !usesSharedRecovery) {
          // 共享恢复已按原快照撤销许可，重复 clear 会误删另一进程的新登录。
          try {
            await internalCredentialVault.clear();
          } on Object {
            /* 原错误仍然保留。 */
          }
          if (!internalRecoveryIsCurrent(request.epoch)) return null;
        }
        result = ControllerRecoveryStopped(
          error is CredentialVaultException ||
                  error is SecureMaterialException ||
                  (error is BackendException &&
                      (error.code == UbaaErrorCode.authenticationRequired ||
                          error.code == UbaaErrorCode.invalidCredentials ||
                          error.code == UbaaErrorCode.upstreamChanged))
              ? SessionRecoveryStatus.needsLogin
              : SessionRecoveryStatus.unavailable,
          error: internalRecordFailure(
            error,
            DiagnosticOperation.initialization,
            stackTrace: stackTrace,
          ),
          transientFailure: controllerTemporaryRecoveryFailure(error),
        );
      }
      await _publishRecoveryResult(request, result);
      return result;
    }
  }

  Future<void> _publishRecoveryResult(
    RecoveryRequest request,
    ControllerRecoveryResult result,
  ) async {
    final epoch = request.epoch;
    if (!internalRecoveryIsCurrent(epoch)) return;
    void publishSession() {
      if (!internalRecoveryIsCurrent(epoch))
        throw const RecoveryInterrupted(RecoveryStopReason.superseded);
      final session = result.forSession(targetOnly: request.targetOnly);
      internalSessionRecoveryStatus = session.status;
      internalError = session.error;
      if (result case ControllerRecoveredSession(:final profile)) {
        internalUser = profile;
        internalInvalidateReadPlansAfterLogin(request);
      }
    }

    if (result case ControllerRecoveredSession(:final deliveryScope)) {
      if (deliveryScope == null) {
        publishSession();
      } else {
        // 最后一个 await 后仍须核对持久身份，并在同一交付边界发布。
        await deliveryScope.commitDelivery(publishSession);
      }
      if (!internalRecoveryIsCurrent(epoch) ||
          (deliveryScope != null && !deliveryScope.isCurrent))
        return;
      if (internalBackend
          case final ConfirmedAppServiceAccountBackend service) {
        service.confirmAppServiceAccount();
      }
      unawaited(internalAutomaticSchoolAction(internalQueueProfileRefresh));
      // 共享身份重绑后使用新读取修订，避免合并到已撤销的旧任务。
      unawaited(internalLoadWriteReadbacks(force: deliveryScope != null));
      internalNotify();
      for (final entry in request.queriesAfterRebuild.entries) {
        if (!internalRecoveryIsCurrent(epoch)) return;
        if (internalSnapshots[entry.key]!.readContext?.hasSameQuery(
              entry.value,
            ) ==
            true)
          unawaited(
            internalAutomaticSchoolAction(
              () => internalRefreshFeatureQuery(entry.key, entry.value),
            ),
          );
      }
      request.queriesAfterRebuild.clear();
      if (request.refreshHomeAfter) internalPendingHomeRecoveryEpoch = epoch;
    } else {
      publishSession();
      if (result case ControllerRecoveryVerification(
        :final input,
        :final route,
      )) {
        await internalResumeRequiredCaptcha(input, route);
      }
    }
    if (!internalRecoveryIsCurrent(epoch)) return;
    internalFeatureRecoveryStates[request.feature] = result.status;
    if (result.error case final error?) {
      internalFeatureRecoveryErrors[request.feature] = error;
    } else {
      internalFeatureRecoveryErrors.remove(request.feature);
    }
  }

  @internal
  Future<void> internalRequireReadSession({FeatureId? feature}) async {
    if (!internalUsesLocalRecovery) return;
    if (internalBackend is RequiredSessionBackend &&
        feature != null &&
        recoveryStatusFor(feature) == SessionRecoveryStatus.ready)
      return;
    final pending = internalSessionRecoveryFuture;
    if (pending != null) await pending;
    if (internalDisposed)
      throw const BackendException(UbaaErrorCode.operationConflict);
    if (internalSessionRecoveryStatus != SessionRecoveryStatus.ready) {
      throw BackendException(
        internalSessionRecoveryStatus == SessionRecoveryStatus.unavailable
            ? UbaaErrorCode.networkError
            : UbaaErrorCode.authenticationRequired,
      );
    }
  }

  @internal
  Future<void> internalRetainCurrentAccount({
    required String username,
    required bool retainSession,
  }) async {
    final store = internalLocalAccountStore;
    if (store == null || internalUser == null) return;
    final scope = internalCaptureSessionScope();
    final epoch = scope.lifecycle;
    try {
      final index = await store.retain(username, retainSession: retainSession);
      if (!scope.isCurrent) return;
      if (store is SecureLocalAccountStore) {
        final shared = await store.capture();
        if (!scope.isCurrent) return;
        if (shared == null || shared.state.generation != index.generation) {
          throw const RecoveryInterrupted(RecoveryStopReason.superseded);
        }
        internalSharedAccountSnapshot = shared;
        if (internalBackend case final SharedAccountBackend backend) {
          await backend.bindSharedAccount(
            await store.bindSnapshot(shared, requireRestore: false),
          );
        }
      }
      internalLocalAccount = index.account;
      if (scope.backend case final ConfirmedAppServiceAccountBackend service) {
        service.confirmAppServiceAccount();
      }
      internalUsesLocalRecovery = true;
      if (index.account != null) {
        // 手动登录已沿原userInfo读取完整资料；不让随后开启的磁盘读取倒退展示。
        internalProfileDisplay = profileDisplay(
          internalUser!,
          null,
          null,
          accountScope: index.account!.id,
        );
        internalProfileDisplayEpoch = epoch;
        await internalRestoreCachedHome(index.account!);
      }
    } on Object catch (error, stackTrace) {
      if (!scope.isCurrent) return;
      // 在线登录成功与能否保留本机材料是两件事，保存失败不得假装未登录。
      internalError = internalRecordFailure(
        error,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
    }
  }
}

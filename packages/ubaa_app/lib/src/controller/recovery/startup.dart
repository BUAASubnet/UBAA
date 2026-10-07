import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/profile.dart';
import 'package:ubaa_app/src/contracts/routing.dart';
import 'package:ubaa_app/src/contracts/recovery.dart';
import 'retry.dart' show controllerTemporaryRecoveryFailure;
import '../state/models.dart' show RecoveryRequest;
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase, SessionRecoveryStatus;

mixin ControllerOfflineStartup on ControllerState {
  @internal
  Future<bool> internalInitializeLocalHome() async {
    final epoch = internalLifecycleEpoch;
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
      internalLocalAccount = index.account;
      internalUser = UserSummary(username: index.account!.username);
      internalLoginForm = internalLoginForm.copyWith(
        username: index.account!.username,
      );
      internalUsesLocalRecovery = true;
      internalSessionRecoveryStatus = SessionRecoveryStatus.idle;
      // 先登记本地打开任务，状态通知中的详情读取也能等待同一账号句柄。
      // 不等待磁盘，首页首帧仍只依赖轻量账号索引。
      unawaited(internalRestoreCachedHome(index.account!));
      internalSetPhase(AppPhase.home);
      if (internalHomeFrameReported) {
        // backend 在已展示首页后被显式替换时不会再产生新的首帧；仍须
        // 沿既有恢复任务重新核对继任实例的会话和身份。
        unawaited(recoverSession());
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
  }) {
    if (internalDisposed ||
        internalIsSigningOut ||
        internalClearingBusinessCache ||
        !internalUsesLocalRecovery ||
        internalPhase != AppPhase.home)
      return Future<void>.value();
    final active = internalActiveRecovery;
    if (active != null && active.feature == feature) {
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

  @internal
  Future<void> internalPerformSessionRecovery(
    RecoveryRequest request, {
    bool allowRebuild = true,
  }) async {
    final epoch = request.epoch;
    try {
      if (internalBackend case final RouteSettingsBackend settings) {
        final result = await settings.routeSettings();
        if (!internalRecoveryIsCurrent(epoch)) return;
        internalApplyRouteSettings(result);
      }
      final backend = internalBackend;
      final profile = backend is RequiredSessionBackend
          ? await internalRecoverRequiredProfile(
              backend as RequiredSessionBackend,
              request.feature,
              epoch,
            )
          : await internalRecoverLegacyProfile(epoch);
      if (!internalRecoveryIsCurrent(epoch)) return;
      if (profile == null) {
        internalSessionRecoveryStatus = SessionRecoveryStatus.needsLogin;
        return;
      }
      final expected = internalLocalAccount?.username ?? internalUser?.username;
      if (expected != null &&
          profile.username != expected &&
          profile.schoolId != expected) {
        // 禁止把另一账号的在线结果绑定到旧账号的本地内容。
        await internalRejectMismatchedAccount();
        return;
      }
      await internalRefreshRouteSettings();
      if (!internalRecoveryIsCurrent(epoch)) return;
      internalUser = profile;
      internalError = null;
      internalSessionRecoveryStatus = SessionRecoveryStatus.ready;
      unawaited(internalQueueProfileRefresh());
      unawaited(internalLoadWriteReadbacks());
      internalInvalidateReadPlansAfterLogin(request);
      internalNotify();
      for (final entry in request.queriesAfterRebuild.entries) {
        if (!internalRecoveryIsCurrent(epoch)) return;
        if (internalSnapshots[entry.key]!.readContext?.hasSameQuery(
              entry.value,
            ) ==
            true)
          unawaited(refreshFeatureQuery(entry.key, entry.value));
      }
      request.queriesAfterRebuild.clear();
      if (request.refreshHomeAfter) internalPendingHomeRecoveryEpoch = epoch;
    } on Object catch (caughtError, caughtStackTrace) {
      Object error = caughtError;
      StackTrace stackTrace = caughtStackTrace;
      if (!internalRecoveryIsCurrent(epoch)) return;
      if (allowRebuild && error is BackendException && error.clientDisposed) {
        try {
          if (await internalRebuildDuringRecovery(request)) {
            await internalPerformSessionRecovery(request, allowRebuild: false);
            return;
          }
        } on Object catch (replacementError, replacementTrace) {
          error = replacementError;
          stackTrace = replacementTrace;
        }
        if (!internalRecoveryIsCurrent(request.epoch)) return;
      }
      request.transientFailure = controllerTemporaryRecoveryFailure(error);
      if (error is BackendException &&
          (error.code == UbaaErrorCode.invalidCredentials ||
              error.code == UbaaErrorCode.upstreamChanged)) {
        internalAutomaticCredentialBlocked = true;
      }
      if (error is BackendException &&
          error.code == UbaaErrorCode.invalidCredentials) {
        try {
          await internalCredentialVault.clear();
        } on Object {
          /* 原错误仍然保留。 */
        }
        if (!internalRecoveryIsCurrent(request.epoch)) return;
      }
      internalError = internalRecordFailure(
        error,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
      internalSessionRecoveryStatus =
          error is CredentialVaultException ||
              error is SecureMaterialException ||
              (error is BackendException &&
                  (error.code == UbaaErrorCode.authenticationRequired ||
                      error.code == UbaaErrorCode.invalidCredentials ||
                      error.code == UbaaErrorCode.upstreamChanged))
          ? SessionRecoveryStatus.needsLogin
          : SessionRecoveryStatus.unavailable;
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
    final epoch = internalLifecycleEpoch;
    try {
      final index = await store.retain(username, retainSession: retainSession);
      if (internalDisposed || epoch != internalLifecycleEpoch) return;
      internalLocalAccount = index.account;
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
      // 在线登录成功与能否保留本机材料是两件事，保存失败不得假装未登录。
      internalError = internalRecordFailure(
        error,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
    }
  }
}

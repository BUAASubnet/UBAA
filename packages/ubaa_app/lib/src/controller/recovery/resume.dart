import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import '../state/activity.dart';
import '../state/recovery_result.dart';
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase, SessionRecoveryStatus;

mixin ControllerDeferredRecovery on ControllerState {
  @internal
  bool get internalRecoveryMustWait =>
      !internalAppForeground ||
      isLoggingIn ||
      internalInteractiveEngaged ||
      internalActivities.hasActive ||
      internalWriteCoordinator.hasPendingOperation;

  @internal
  void internalCancelDeferredRecovery() {
    internalClearRecoveryRetries();
    final requests = internalQueuedRecoveries.values.toList();
    internalQueuedRecoveries.clear();
    internalPendingHomeRecoveryEpoch = null;
    for (final request in requests) {
      if (!request.completion.isCompleted) request.completion.complete();
    }
  }

  @internal
  void internalDrainDeferredRecovery() {
    if ((internalQueuedRecoveries.isEmpty &&
            internalPendingHomeRecoveryEpoch == null) ||
        internalDeferredRecoveryScheduled)
      return;
    if (internalDisposed ||
        internalIsSigningOut ||
        internalPhase == AppPhase.login) {
      internalCancelDeferredRecovery();
      return;
    }
    if (internalPhase != AppPhase.home ||
        internalRecoveryMustWait ||
        internalActiveRecovery != null)
      return;
    internalDeferredRecoveryScheduled = true;
    scheduleMicrotask(() {
      internalDeferredRecoveryScheduled = false;
      internalStartNextRecovery();
    });
  }

  @internal
  void internalStartNextRecovery() {
    if (internalDisposed ||
        internalIsSigningOut ||
        internalPhase != AppPhase.home) {
      internalCancelDeferredRecovery();
      return;
    }
    if (internalActiveRecovery != null || internalRecoveryMustWait) return;
    for (final request in internalQueuedRecoveries.values.toList()) {
      if (request.epoch != internalLifecycleEpoch ||
          request.networkRevision != internalNetworkRevision ||
          (request.deadline?.isBefore(DateTime.now()) ?? false)) {
        internalQueuedRecoveries.remove(request.feature);
        request.completion.complete();
      }
    }
    if (internalQueuedRecoveries.isEmpty) {
      final epoch = internalPendingHomeRecoveryEpoch;
      internalPendingHomeRecoveryEpoch = null;
      if (epoch == internalLifecycleEpoch)
        unawaited(internalAutomaticSchoolAction(internalRefreshHome));
      return;
    }
    // 已发送检查不可抢占；下个安全边界先处理用户显式目标。
    final explicit = internalQueuedRecoveries.values.where(
      (request) => request.interactive,
    );
    final request = explicit.isEmpty
        ? internalQueuedRecoveries.values.first
        : explicit.first;
    internalQueuedRecoveries.remove(request.feature);
    internalActiveRecovery = request;
    internalSessionRecoveryFuture = request.completion.future;
    request.targetOnly = internalTargetRecoveryOnly && request.deadline == null;
    final activity = internalActivities.begin(ControllerActivityKind.recovery);
    internalError = null;
    // 单项目标恢复只标记该功能，全局状态保持已就绪，首页不进入“连接中”。
    if (!request.targetOnly)
      internalSessionRecoveryStatus = SessionRecoveryStatus.restoring;
    internalFeatureRecoveryStates[request.feature] =
        SessionRecoveryStatus.restoring;
    internalWriteCoordinator.invalidate();
    internalNotify();
    ControllerRecoveryResult? result;
    unawaited(
      internalPerformSessionRecovery(request)
          .then<void>((value) {
            result = value;
          })
          .whenComplete(() {
            activity.finish();
            internalActiveRecovery = null;
            internalSessionRecoveryFuture = null;
            internalFinishRecoveryRetry(request, result);
            request.completion.complete();
            if (!internalDisposed) internalNotify();
          }),
    );
  }
}

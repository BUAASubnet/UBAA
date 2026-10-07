import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase, SessionRecoveryStatus;

mixin ControllerDeferredRecovery on ControllerState {
  @internal
  bool get internalRecoveryMustWait =>
      !internalAppForeground ||
      isLoggingIn ||
      internalInteractiveEngaged ||
      internalWriteTransitions != 0 ||
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
      if (request.epoch != internalLifecycleEpoch) {
        internalQueuedRecoveries.remove(request.feature);
        request.completion.complete();
      }
    }
    if (internalQueuedRecoveries.isEmpty) {
      final epoch = internalPendingHomeRecoveryEpoch;
      internalPendingHomeRecoveryEpoch = null;
      if (epoch == internalLifecycleEpoch) unawaited(refreshHome());
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
    internalWriteTransitions++;
    internalError = null;
    internalSessionRecoveryStatus = SessionRecoveryStatus.restoring;
    internalFeatureRecoveryStates[request.feature] =
        SessionRecoveryStatus.restoring;
    internalWriteCoordinator.invalidate();
    internalNotify();
    unawaited(
      internalPerformSessionRecovery(request).whenComplete(() {
        if (internalRecoveryIsCurrent(request.epoch)) {
          internalFeatureRecoveryStates[request.feature] =
              internalSessionRecoveryStatus;
          final error = internalError;
          if (error == null) {
            internalFeatureRecoveryErrors.remove(request.feature);
          } else {
            internalFeatureRecoveryErrors[request.feature] = error;
          }
        }
        internalWriteTransitions--;
        internalActiveRecovery = null;
        internalSessionRecoveryFuture = null;
        internalFinishRecoveryRetry(request);
        request.completion.complete();
        if (!internalDisposed) internalNotify();
      }),
    );
  }
}

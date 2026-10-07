import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import '../state/models.dart'
    show RecoveryRequest, RecoveryRetry, controllerRecoveryRetryDelays;
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase, SessionRecoveryStatus;

bool controllerTemporaryRecoveryFailure(Object? error) {
  final UbaaErrorCode code;
  if (error is BackendException) {
    if (error.accountMismatch || error.retryable == false) return false;
    code = error.code;
  } else if (error is UiError) {
    if (!error.retryable) return false;
    code = error.code;
  } else {
    return false;
  }
  return code == UbaaErrorCode.networkError ||
      code == UbaaErrorCode.timeout ||
      code == UbaaErrorCode.upstreamUnavailable;
}

mixin ControllerRecoveryRetry on ControllerState {
  @internal
  void internalClearRecoveryRetries() {
    internalClearBusinessRetries();
    for (final retry in internalRecoveryRetries.values) {
      retry.timer?.cancel();
    }
    internalRecoveryRetries.clear();
    internalNetworkWakeCooldown?.cancel();
    internalNetworkWakeCooldown = null;
  }

  @internal
  void internalFinishRecoveryRetry(RecoveryRequest request) {
    final previous = internalRecoveryRetries.remove(request.feature);
    previous?.timer?.cancel();
    if (!internalRecoveryIsCurrent(request.epoch) || internalIsSigningOut)
      return;
    if (request.transientFailure) {
      final attempt = ((previous?.attempt ?? -1) + 1).clamp(0, 2);
      internalRecoveryRetries[request.feature] = RecoveryRetry(
        request.epoch,
        attempt,
        internalSnapshots[request.feature]!.readContext?.query,
      );
    } else if (internalSessionRecoveryStatus == SessionRecoveryStatus.ready &&
        previous?.query != null) {
      final query = previous!.query!;
      // 只刷新仍属于原查询的失败页；新选项、草稿与导航由现有读代次保护。
      final context = internalSnapshots[request.feature]!.readContext;
      if (context?.hasSameQuery(query) ?? false) {
        unawaited(internalRefreshFeatureQuery(request.feature, query));
      }
    }
  }

  @internal
  void internalSyncRecoveryRetries() {
    if (internalDisposed ||
        internalIsSigningOut ||
        internalPhase != AppPhase.home) {
      internalClearRecoveryRetries();
      return;
    }
    internalSyncBusinessRetries();
    internalRecoveryRetries.removeWhere((_, retry) {
      if (retry.epoch == internalLifecycleEpoch) return false;
      retry.timer?.cancel();
      return true;
    });
    final wait =
        internalRecoveryMustWait ||
        internalActiveRecovery != null ||
        internalClearingBusinessCache ||
        internalRebuildingBackend;
    for (final entry in internalRecoveryRetries.entries.toList()) {
      final retry = entry.value;
      if (wait) {
        retry.timer?.cancel();
        retry.timer = null;
        continue;
      }
      if (internalQueuedRecoveries.containsKey(entry.key) || retry.queued)
        continue;
      if (retry.due) {
        retry.queued = true;
        scheduleMicrotask(() {
          retry.queued = false;
          if (!identical(internalRecoveryRetries[entry.key], retry) ||
              !internalRecoveryIsCurrent(retry.epoch) ||
              internalRecoveryMustWait ||
              internalClearingBusinessCache ||
              internalRebuildingBackend)
            return;
          retry.due = false;
          unawaited(internalRecoverSession(feature: entry.key));
        });
      } else {
        retry.timer ??= Timer(controllerRecoveryRetryDelays[retry.attempt], () {
          retry.timer = null;
          retry.due = true;
          internalSyncRecoveryRetries();
        });
      }
    }
  }

  @internal
  void internalWakeNetworkRecovery() {
    if (internalDisposed ||
        internalIsSigningOut ||
        !internalAppForeground ||
        !internalUsesLocalRecovery ||
        !internalHomeFrameReported ||
        internalPhase != AppPhase.home ||
        internalAutomaticCredentialBlocked ||
        internalSessionRecoveryStatus == SessionRecoveryStatus.needsLogin ||
        internalNetworkWakeCooldown != null)
      return;
    // 接口变化不代表认证成功；只唤醒临时失败的恢复和读取。
    for (final snapshot in [
      ...internalHomeDefaults.values,
      ...internalSnapshots.values,
    ]) {
      if (controllerTemporaryRecoveryFailure(snapshot.error) &&
          !internalBusinessRetries.keys.any(
            (key) => key.$1 == snapshot.feature,
          )) {
        internalRecoveryRetries.putIfAbsent(
          snapshot.feature,
          () => RecoveryRetry(
            internalLifecycleEpoch,
            0,
            internalSnapshots[snapshot.feature]!.readContext?.query,
          ),
        );
      }
    }
    if (internalRecoveryRetries.isEmpty && internalBusinessRetries.isEmpty)
      return;
    for (final retry in internalBusinessRetries.values) {
      retry.timer?.cancel();
      retry.timer = null;
      if (!retry.running) retry.due = true;
    }
    internalNetworkWakeCooldown = Timer(const Duration(seconds: 30), () {
      internalNetworkWakeCooldown = null;
    });
    for (final retry in internalRecoveryRetries.values) {
      retry.timer?.cancel();
      retry.timer = null;
      retry.due = true;
    }
    internalSyncRecoveryRetries();
  }
}

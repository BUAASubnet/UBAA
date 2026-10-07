import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/contracts/recovery.dart';
import 'retry.dart' show controllerTemporaryRecoveryFailure;
import '../state/models.dart' show BusinessRetry, controllerRecoveryRetryDelays;
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase, SessionRecoveryStatus;

mixin ControllerBusinessRetry on ControllerState {
  @internal
  void internalClearBusinessRetries() {
    for (final retry in internalBusinessRetries.values) {
      retry.timer?.cancel();
    }
    internalBusinessRetries.clear();
  }

  @internal
  void internalBeginBusinessAttempt(
    FeatureId feature,
    FeatureQuery? query,
    int revision,
  ) {
    final key = (feature, query == null);
    final retry = internalBusinessRetries[key];
    if (retry == null) return;
    if (retry.running &&
        retry.epoch == internalLifecycleEpoch &&
        FeatureReadContext(
          query: retry.query,
          requestRevision: 0,
        ).hasSameQuery(query)) {
      retry.revision = revision;
    } else {
      retry.timer?.cancel();
      internalBusinessRetries.remove(key);
    }
  }

  @internal
  void internalFinishBusinessAttempt(
    FeatureId feature,
    FeatureQuery? query,
    int revision,
    int epoch,
    UiError? error,
  ) {
    final key = (feature, query == null);
    final previous = internalBusinessRetries.remove(key);
    previous?.timer?.cancel();
    if (!controllerTemporaryRecoveryFailure(error) ||
        epoch != internalLifecycleEpoch ||
        internalDisposed ||
        internalIsSigningOut ||
        internalPhase != AppPhase.home)
      return;
    // 认证失败交给恢复队列，避免两个退避器同时启动同一个失败范围。
    if (!internalBusinessRetrySessionReady(feature)) return;
    internalBusinessRetries[key] = BusinessRetry(
      epoch,
      revision,
      query,
      previous == null ? 0 : (previous.attempt + 1).clamp(0, 2),
    );
  }

  @internal
  bool internalBusinessRetryCurrent(
    (FeatureId, bool) key,
    BusinessRetry retry,
  ) {
    final snapshot = key.$2
        ? internalHomeDefaults[key.$1]
        : internalSnapshots[key.$1];
    return retry.epoch == internalLifecycleEpoch &&
        snapshot?.readContext?.requestRevision == retry.revision &&
        (snapshot?.readContext?.hasSameQuery(retry.query) ?? false);
  }

  @internal
  bool internalBusinessRetrySessionReady(FeatureId feature) =>
      !internalUsesLocalRecovery ||
      (internalBackend is RequiredSessionBackend
          ? recoveryStatusFor(feature) == SessionRecoveryStatus.ready
          : internalSessionRecoveryStatus == SessionRecoveryStatus.ready);

  @internal
  bool internalBusinessRetryMustWait(FeatureId feature) =>
      internalRecoveryMustWait ||
      internalActiveRecovery != null ||
      internalQueuedRecoveries.isNotEmpty ||
      internalClearingBusinessCache ||
      internalRebuildingBackend ||
      !internalBusinessRetrySessionReady(feature);

  @internal
  void internalSyncBusinessRetries() {
    internalBusinessRetries.removeWhere((key, retry) {
      if (internalBusinessRetryCurrent(key, retry)) return false;
      retry.timer?.cancel();
      return true;
    });
    for (final entry in internalBusinessRetries.entries.toList()) {
      final retry = entry.value;
      if (retry.running) continue;
      if (internalBusinessRetryMustWait(entry.key.$1)) {
        retry.timer?.cancel();
        retry.timer = null;
        continue;
      }
      if (retry.due) {
        retry.running = true;
        scheduleMicrotask(() async {
          if (!identical(internalBusinessRetries[entry.key], retry)) return;
          if (!internalBusinessRetryCurrent(entry.key, retry) ||
              internalBusinessRetryMustWait(entry.key.$1) ||
              internalDisposed ||
              internalIsSigningOut) {
            retry.running = false;
            return;
          }
          retry.due = false;
          try {
            if (retry.query case final query?) {
              await internalRefreshFeatureQuery(entry.key.$1, query);
            } else {
              await internalRefreshHome(only: [entry.key.$1]);
            }
          } finally {
            retry.running = false;
            if (!internalDisposed) internalSyncBusinessRetries();
          }
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
}

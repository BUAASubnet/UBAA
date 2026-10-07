import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/write.dart';
import 'package:ubaa_app/src/write/coordinator.dart';
import 'package:ubaa_app/src/write/receipt_verifier.dart';
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase, SessionRecoveryStatus;

mixin ControllerWriteLifecycle on ControllerState {
  @internal
  WriteCoordinator internalCreateWriteCoordinator(UbaaBackend backend) =>
      WriteCoordinator(
        diagnostics: internalDiagnostics,
        canStart: () =>
            !internalDisposed &&
            !internalInteractiveEngaged &&
            internalSessionRecoveryStatus != SessionRecoveryStatus.needsLogin &&
            internalPhase == AppPhase.home &&
            internalUser != null &&
            internalWriteTransitions == 0 &&
            (!internalUsesLocalRecovery ||
                internalSessionRecoveryStatus == SessionRecoveryStatus.ready),
        // 闭包固定创建时的 backend，晚到 prepare 只能在原实例释放意图。
        commit: (intentId) => internalCommitWriteWithBackend(backend, intentId),
        discard: (intentId) =>
            internalDiscardWriteWithBackend(backend, intentId),
        receiptVerifier: WriteReceiptVerifier(
          refreshAfterWrite: (operation, query) =>
              refreshAfterWrite(operation, query),
          verifyCgyyReceipt: matchesCgyyReceipt,
          verifyCgyyCancellation: verifyCgyyCancellation,
          refreshYgdkAfterWrite: refreshYgdkAfterWrite,
          refreshEvaluationAfterWrite: refreshEvaluationAfterWrite,
        ),
      );

  @internal
  void internalBeginWriteTransition() {
    internalLockDisplay?.cancel();
    // 必须先禁止入口，再发出 invalidate 通知，覆盖监听器同步重入。
    internalWriteTransitions++;
    internalLifecycleEpoch++;
    internalReadCacheEpoch++;
    internalYgdkGeneration++;
    internalWriteCoordinator.invalidate();
  }

  @internal
  void internalEndWriteTransition() {
    internalWriteTransitions--;
    internalDrainDeferredRecovery();
    internalPumpReadTasks();
  }

  @internal
  void internalReplaceWriteCoordinator(UbaaBackend backend) {
    internalWriteCoordinator.removeListener(internalNotify);
    internalWriteCoordinator.dispose();
    internalWriteCoordinator = internalCreateWriteCoordinator(backend);
    internalWriteCoordinator.addListener(internalNotify);
  }

  @internal
  Future<WriteCommitResult> internalCommitWriteWithBackend(
    UbaaBackend backend,
    String intentId,
  ) async {
    if (backend is! WriteCommitBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    if (intentId.trim().isEmpty) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    final account = internalLocalAccount;
    if (backend is CacheWriteBackend && account != null) {
      return internalCommitWithAccountCache(
        backend as CacheWriteBackend,
        intentId,
        account.id,
      );
    }
    return (backend as WriteCommitBackend).commitWrite(intentId);
  }

  @internal
  Future<void> internalDiscardWriteWithBackend(
    UbaaBackend backend,
    String intentId,
  ) async {
    if (backend is! WriteCommitBackend) {
      throw const BackendException(UbaaErrorCode.unsupported);
    }
    final normalized = intentId.trim();
    if (normalized.isEmpty) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return (backend as WriteCommitBackend).discardWriteIntent(normalized);
  }
}

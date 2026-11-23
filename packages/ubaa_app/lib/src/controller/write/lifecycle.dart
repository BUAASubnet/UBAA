import 'dart:async';
import 'pinned_readback.dart';
import 'library_readback.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/contracts/recovery.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/write.dart';
import 'package:ubaa_app/src/contracts/write_readback.dart';
import 'package:ubaa_app/src/write/coordinator.dart';
import 'package:ubaa_app/src/write/receipt_verifier.dart';
import '../state/activity.dart';
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase, SessionRecoveryStatus;

mixin ControllerWriteLifecycle on ControllerState {
  @internal
  WriteCoordinator internalCreateWriteCoordinator(UbaaBackend backend) =>
      WriteCoordinator(
        diagnostics: internalDiagnostics,
        dismissVerifiedLibraryHint: (id) async {
          final account = internalLocalAccount?.id;
          final epoch = internalLifecycleEpoch;
          if (backend is! WriteReadbackBackend ||
              account == null ||
              !internalReadbackCurrent(backend, account, epoch))
            return;
          await (backend as WriteReadbackBackend).dismissWriteReadbackHint(
            id,
            accountId: account,
          );
          if (internalReadbackCurrent(backend, account, epoch))
            await internalLoadWriteReadbacks(force: true);
        },
        recoverSigninSession: backend is RequiredSessionBackend
            ? _recoverSigninSession
            : null,
        observeResult: (operation, {required error, required route}) =>
            internalRecordOperationOutcome(
              operation == WriteOperation.libraryLoanRenew
                  ? 'library_loans'
                  : operation.feature?.wireName ?? 'bhpan',
              write: true,
              error: error,
              route: route,
            ),
        canStart: () =>
            !internalDisposed &&
            !internalInteractiveEngaged &&
            internalSessionRecoveryStatus != SessionRecoveryStatus.needsLogin &&
            internalPhase == AppPhase.home &&
            internalUser != null &&
            internalNetworkOnline &&
            !internalNetworkChecking &&
            internalNetworkFailure == null &&
            !internalActivities.hasActive &&
            (!internalUsesLocalRecovery ||
                internalSessionRecoveryStatus == SessionRecoveryStatus.ready),
        // 闭包固定创建时的 backend，晚到 prepare 只能在原实例释放意图。
        commit: (intentId) => internalUserSchoolAction(
          () => internalCommitWriteWithBackend(backend, intentId),
        ),
        discard: (intentId) =>
            internalDiscardWriteWithBackend(backend, intentId),
        receiptVerifier: WriteReceiptVerifier(
          refreshPinnedAfterWrite: backend is PinnedWriteReadbackBackend
              ? (operation, query, route) =>
                    controllerPinnedWriteReadback(this, operation, query, route)
              : null,
          refreshAfterWrite: (operation, query) =>
              refreshAfterWrite(operation, query),
          verifyCgyyReceipt: matchesCgyyReceipt,
          verifyCgyyCancellation: verifyCgyyCancellation,
          refreshYgdkAfterWrite: refreshYgdkAfterWrite,
          refreshEvaluationAfterWrite: refreshEvaluationAfterWrite,
          verifyLibraryLoanRenew: (intent) =>
              controllerVerifyLibraryLoanRenew(this, intent),
        ),
      );

  Future<bool> _recoverSigninSession(BackendException error) async {
    final session = internalCaptureSessionScope();
    final network = internalNetworkRevision;
    final credentials = internalLoginCredentialRevision;
    bool current() =>
        session.isCurrent &&
        internalAppForeground &&
        internalPhase == AppPhase.home &&
        network == internalNetworkRevision &&
        credentials == internalLoginCredentialRevision;

    if (!internalUsesLocalRecovery || !current()) throw error;
    internalRecordSessionExpired(FeatureId.signin, error.resolvedRoute);
    try {
      await internalScheduleReadAuthentication(
        FeatureId.signin,
        ReadPriority.urgent,
        current,
        force: true,
      );
    } on Object {
      if (!current()) return false;
      rethrow;
    }
    return current();
  }

  @internal
  ControllerActivity internalBeginOperationTransition(
    ControllerActivityKind kind,
  ) {
    if (kind == ControllerActivityKind.authentication ||
        kind == ControllerActivityKind.routeChange) {
      internalCancelNetworkChange();
    }
    internalLockDisplay?.cancel();
    // 必须先禁止入口，再发出 invalidate 通知，覆盖监听器同步重入。
    final activity = internalActivities.begin(kind);
    internalSessionLifecycle.invalidate();
    internalCacheLifecycle.invalidateReads();
    internalYgdkGeneration++;
    internalWriteCoordinator.invalidate();
    return activity;
  }

  @internal
  void internalEndOperationTransition(ControllerActivity activity) {
    activity.finish();
    internalDrainDeferredRecovery();
    internalPumpReadTasks();
  }

  @internal
  void internalReplaceWriteCoordinator(
    UbaaBackend backend, {
    bool sameSession = false,
  }) {
    final previous = internalWriteCoordinator;
    previous.removeListener(internalNotify);
    previous.dispose();
    internalWriteCoordinator = internalCreateWriteCoordinator(backend);
    if (sameSession) internalWriteCoordinator.inheritLibraryReadbacks(previous);
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

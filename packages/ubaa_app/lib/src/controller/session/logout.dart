import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/lifecycle.dart';
import '../state/activity.dart';
import '../state/state.dart' show ControllerState, LocalDataOwnerScope;
import '../state/types.dart'
    show AppPhase, LoginFormState, SessionRecoveryStatus;

mixin ControllerLocalData on ControllerState {
  @internal
  LocalDataOwnerScope get internalLocalDataOwnerScope =>
      LocalDataOwnerScope.capture(this);
}

mixin ControllerLogout on ControllerState {
  @internal
  Future<void> internalLogoutController({
    required bool clearSavedCredential,
    Future<void> Function()? clearLocalData,
  }) async {
    if (internalDisposed || internalIsSigningOut) {
      if (clearSavedCredential) {
        throw const BackendException(UbaaErrorCode.operationConflict);
      }
      return;
    }
    internalCancelLoginVerification(notify: false);
    internalSessionLifecycle.beginSignOut();
    internalInPlaceLogin = false;
    internalInteractiveInPlace = false;
    internalCredentialRestoreAllowed = false;
    internalManualAuthenticationRequired = true;
    internalCancelDeferredRecovery();
    final activity = internalBeginOperationTransition(
      ControllerActivityKind.signOut,
    );
    internalSessionRecoveryStatus = SessionRecoveryStatus.signedOut;
    internalUser = null;
    internalActiveRoutes = const <ConnectionMode>[];
    internalLoginForm = internalLoginForm.copyWith(password: '', captcha: '');
    internalResetFeatureSnapshots();
    internalSetPhase(AppPhase.login);
    (Object, StackTrace)? failure;
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } on Object catch (error, stackTrace) {
        failure ??= (error, stackTrace);
        internalError = internalRecordFailure(
          error,
          DiagnosticOperation.logout,
          stackTrace: stackTrace,
        );
      }
    }

    // 先同步撤销日程代次，不能等待安全索引或后端工厂后才拒绝旧结果。
    final agendaClosed = attempt(internalCloseAgenda);
    var ownsCleanup = true;
    SharedAccountBinding? revokedBinding;
    LocalAccountSnapshot? cleanupSnapshot;
    final indexClosed = attempt(() async {
      final accounts = internalLocalAccountStore;
      final backend = internalBackend;
      final snapshot = internalSharedAccountSnapshot;
      if (accounts is SecureLocalAccountStore &&
          backend is SharedAccountBackend) {
        ownsCleanup = false;
        if (snapshot == null) throw const LocalAccountConflict();
        final revoked = await accounts.revokeBinding(snapshot);
        revokedBinding = revoked;
        internalSharedAccountSnapshot = revoked.snapshot;
        ownsCleanup = true;
      } else {
        await accounts?.signOut();
      }
    });
    try {
      await indexClosed;
      await internalBackendRebuildCompletion?.future;
      if (internalDisposed) {
        if (clearSavedCredential)
          throw const CredentialVaultException(
            CredentialVaultErrorCode.storageFailure,
          );
        return;
      }
      await agendaClosed;
      final backend = internalBackend;
      final revoked = revokedBinding;
      if (ownsCleanup &&
          revoked != null &&
          backend is SharedAccountLogoutBackend) {
        await attempt(
          () => (backend as SharedAccountLogoutBackend).logoutSharedAccount(
            revoked,
            clearCache: clearSavedCredential,
          ),
        );
      } else {
        await attempt(
          () => internalCloseOfflineAccount(
            remove: clearSavedCredential && ownsCleanup,
          ),
        );
        if (ownsCleanup) await attempt(internalBackend.logout);
      }
      if (clearSavedCredential && ownsCleanup) {
        if (internalDisposed)
          throw const CredentialVaultException(
            CredentialVaultErrorCode.storageFailure,
          );
        await attempt(
          () => internalMutateCredential(internalLifecycleEpoch, () async {
            final accounts = internalLocalAccountStore;
            final snapshot = revokedBinding?.snapshot;
            if (accounts is SecureLocalAccountStore &&
                internalBackend is SharedAccountBackend) {
              if (snapshot == null) throw const LocalAccountConflict();
              await accounts.materials.coordinate(() async {
                if (!await accounts.validate(snapshot, requireRestore: false))
                  throw const LocalAccountConflict();
                await internalCredentialVault.clear();
                cleanupSnapshot = await accounts.capture();
              });
            } else {
              await internalCredentialVault.clear();
            }
          }),
        );
        if (internalDisposed)
          throw const CredentialVaultException(
            CredentialVaultErrorCode.storageFailure,
          );
        if (clearLocalData != null)
          await attempt(() async {
            final accounts = internalLocalAccountStore;
            final snapshot = cleanupSnapshot;
            if (accounts is SecureLocalAccountStore &&
                internalBackend is SharedAccountBackend) {
              if (snapshot == null) throw const LocalAccountConflict();
              // Core 缓存已在前段清理；这里仅执行账号固定的本机偏好回调。
              await accounts.materials.coordinate(() async {
                if (!await accounts.validate(snapshot, requireRestore: false))
                  throw const LocalAccountConflict();
                await clearLocalData();
              });
            } else {
              await clearLocalData();
            }
          });
      }
      if (!internalDisposed) {
        internalUser = null;
        internalActiveRoutes = const <ConnectionMode>[];
        internalLoginForm = clearSavedCredential && failure == null
            ? LoginFormState(routePolicy: internalLoginForm.routePolicy)
            : internalLoginForm.copyWith(password: '', captcha: '');
        internalResetFeatureSnapshots();
        internalSetPhase(AppPhase.login);
      }
      if (clearSavedCredential && failure != null) {
        Error.throwWithStackTrace(failure!.$1, failure!.$2);
      }
    } finally {
      await agendaClosed;
      internalSessionLifecycle.endSignOut();
      internalEndOperationTransition(activity);
    }
  }
}

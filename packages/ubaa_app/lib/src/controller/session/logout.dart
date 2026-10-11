import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
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
    internalBeginWriteTransition();
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

    try {
      await internalBackendRebuildCompletion?.future;
      if (internalDisposed) {
        if (clearSavedCredential)
          throw const CredentialVaultException(
            CredentialVaultErrorCode.storageFailure,
          );
        return;
      }
      await attempt(() async => internalLocalAccountStore?.signOut());
      // 必须保持Core清除成功后才移除账号密钥的原有顺序。
      await attempt(
        () => internalCloseOfflineAccount(remove: clearSavedCredential),
      );
      await attempt(internalBackend.logout);
      if (clearSavedCredential) {
        if (internalDisposed)
          throw const CredentialVaultException(
            CredentialVaultErrorCode.storageFailure,
          );
        await attempt(
          () => internalMutateCredential(
            internalLifecycleEpoch,
            internalCredentialVault.clear,
          ),
        );
        if (internalDisposed)
          throw const CredentialVaultException(
            CredentialVaultErrorCode.storageFailure,
          );
        if (clearLocalData != null) await attempt(clearLocalData);
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
      internalSessionLifecycle.endSignOut();
      internalEndWriteTransition();
    }
  }
}

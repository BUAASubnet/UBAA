import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/recovery.dart';
import '../../contracts/session_recovery.dart';
import '../../services/session_recovery.dart';
import '../state/state.dart' show ControllerState;

mixin ControllerRequiredRecovery on ControllerState {
  @internal
  Future<LoginInput?> internalApprovedRecoveryInput(int epoch) async {
    if (internalManualAuthenticationRequired ||
        internalAutomaticCredentialBlocked ||
        internalAutomaticLoginDisabled)
      return null;
    final revision = internalLoginCredentialRevision;
    final saved = await internalCredentialVault.read();
    if (!internalRecoveryIsCurrent(epoch) ||
        revision != internalLoginCredentialRevision ||
        internalManualAuthenticationRequired ||
        internalAutomaticCredentialBlocked ||
        internalAutomaticLoginDisabled)
      return null;
    if (saved == null ||
        !saved.isUsable ||
        !saved.autoLogin ||
        !internalCredentialVault.isAvailable ||
        (internalLocalAccount != null &&
            saved.username != internalLocalAccount!.username) ||
        (internalLocalAccount == null &&
            internalUser != null &&
            saved.username != internalUser!.username &&
            saved.username != internalUser!.schoolId))
      return null;
    return LoginInput(
      username: saved.username,
      password: saved.password,
      rememberPassword: true,
      autoLogin: true,
      routePolicy: internalLoginForm.routePolicy,
    );
  }

  @internal
  Future<UserSummary?> internalRecoverRequiredProfile(
    RequiredSessionBackend backend,
    FeatureId feature,
    int epoch,
  ) async {
    final target =
        internalActiveRecovery?.refreshHomeAfter == true &&
            backend is RequiredTargetSessionBackend
        ? RecoveryTarget.connection
        : RecoveryTarget.fromFeature(feature);
    final result = await internalRecoverTargetSession(
      backend,
      target,
      epoch,
      publishReusedSession:
          internalActiveRecovery?.targetOnly != true ||
          internalActiveRecovery?.refreshHomeAfter == true,
    );
    if (result == null) return null;
    internalSharedRecoveryScope = result.scope;
    if (result.disposition == RecoveryDisposition.reauthenticated) {
      internalActiveRecovery?.replacedRoute = result.session.route;
    }
    internalRecoveredRoute = result.session.route;
    return result.session.profile;
  }

  @internal
  Future<RecoveryResult?> internalRecoverTargetSession(
    RequiredSessionBackend backend,
    RecoveryTarget target,
    int epoch, {
    required bool publishReusedSession,
  }) async {
    final session = internalCaptureSessionScope();
    final account = internalLocalAccount;
    final expected =
        account?.username ?? internalUser?.schoolId ?? internalUser?.username;
    if (expected == null) return null;
    final routeGeneration = internalRoutePolicyGeneration;
    final networkRevision = internalNetworkRevision;
    final credentials = internalLoginCredentialRevision;
    final service = internalRequiredRecoveryServices.putIfAbsent(
      session.backend,
      () => RequiredSessionRecovery(
        backend: backend,
        credentials: internalCredentialVault,
        beforeSharedRebind: () {
          // 重绑开始即作废旧读取，不能等新会话发布后才撤销迟到错误。
          internalWriteReadbackRevision++;
          internalWriteReadbackLoadedEpoch = -1;
          for (final read in internalReadScopes) {
            if (read.valid && (read.task != null || read.preparing)) {
              read.restartRequested = true;
              read.task?.cancel();
            }
          }
          if (internalActiveRecovery case final request?) {
            request.replacedAllRoutes = true;
            internalInvalidateReadPlansAfterLogin(request);
          }
        },
        rebuildBackend: internalLocalAccountStore is SecureLocalAccountStore
            ? (_) async => throw const BackendException(
                UbaaErrorCode.operationConflict,
                clientDisposed: true,
              )
            : null,
      ),
    );
    bool current() =>
        session.isCurrent &&
        networkRevision == internalNetworkRevision &&
        internalNetworkFailure == null &&
        internalRecoveryIsCurrent(epoch) &&
        internalLocalAccount?.id == account?.id &&
        routeGeneration == internalRoutePolicyGeneration &&
        credentials == internalLoginCredentialRevision &&
        !internalRoutePolicyInFlight;
    final store = internalLocalAccountStore;
    final scope = store is SecureLocalAccountStore
        ? await RecoveryScope.capture(
            accounts: store,
            snapshot: internalSharedAccountSnapshot,
            routeGeneration: routeGeneration,
            backendGeneration: epoch,
            credentialGeneration: credentials,
            routePolicy: internalLoginForm.routePolicy,
            allowAutomaticLogin:
                account != null &&
                !internalAutomaticCredentialBlocked &&
                !internalAutomaticLoginDisabled &&
                !internalManualAuthenticationRequired,
            publishReusedSession: publishReusedSession,
            isCurrent: current,
          )
        : RecoveryScope(
            accountAlias: account?.id ?? '',
            expectedUsername: expected,
            accountGeneration: epoch,
            publishReusedSession: publishReusedSession,
            routeGeneration: routeGeneration,
            backendGeneration: epoch,
            credentialGeneration: credentials,
            routePolicy: internalLoginForm.routePolicy,
            allowAutomaticLogin:
                account != null &&
                !internalAutomaticCredentialBlocked &&
                !internalAutomaticLoginDisabled &&
                !internalManualAuthenticationRequired,
            isCurrent: current,
          );
    if (scope.accountAlias != (account?.id ?? ''))
      throw const RecoveryInterrupted(RecoveryStopReason.superseded);
    if (internalActiveRecovery != null) internalSharedRecoveryScope = scope;
    final result = await service.ensureTargetSession(
      target: target,
      scope: scope,
      deadline:
          internalActiveRecovery?.deadline ??
          internalNetworkDeadline ??
          DateTime.now().add(const Duration(minutes: 2)),
    );
    await scope.validatePersistent();
    if (!scope.isCurrent) return null;
    internalSharedAccountSnapshot = scope.sharedSnapshot;
    return result;
  }

  @internal
  Future<UserSummary?> internalRecoverLegacyProfile(int epoch) async {
    final status = await internalBackend.authStatus();
    if (!internalRecoveryIsCurrent(epoch)) return null;
    if (status == AuthStatus.signedOut) {
      final input = await internalApprovedRecoveryInput(epoch);
      if (!internalRecoveryIsCurrent(epoch) || input == null) return null;
      await internalBackend.login(input);
      if (!internalRecoveryIsCurrent(epoch)) return null;
      internalActiveRecovery?.replacedAllRoutes = true;
    }
    return internalBackend.userInfo();
  }
}

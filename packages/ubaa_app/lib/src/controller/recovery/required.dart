import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/recovery.dart';
import '../state/state.dart' show ControllerState;

mixin ControllerRequiredRecovery on ControllerState {
  @internal
  Future<LoginInput?> internalApprovedRecoveryInput(int epoch) async {
    if (internalAutomaticCredentialBlocked) return null;
    final saved = await internalCredentialVault.read();
    if (!internalRecoveryIsCurrent(epoch)) return null;
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
    RecoveredRouteSession recovered;
    try {
      recovered = await backend.recoverRequiredSession(feature);
    } on BackendException catch (error) {
      if (!internalRecoveryIsCurrent(epoch)) return null;
      // 只使用 Core 已返回的目标；无路线或临时故障不能尝试提交密码。
      if (error.code != UbaaErrorCode.authenticationRequired ||
          error.resolvedRoute == null)
        rethrow;
      final input = await internalApprovedRecoveryInput(epoch);
      if (!internalRecoveryIsCurrent(epoch)) return null;
      if (input == null) rethrow;
      recovered = await backend.loginRequiredRoute(error.resolvedRoute!, input);
      if (recovered.route != error.resolvedRoute)
        throw const BackendException(UbaaErrorCode.upstreamChanged);
      internalActiveRecovery?.replacedRoute = recovered.route;
    }
    if (!internalRecoveryIsCurrent(epoch)) return null;
    internalRecoveredRoute = recovered.route;
    return recovered.profile;
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

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/interactive_auth.dart';
import 'package:ubaa_app/src/contracts/routing.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../state/activity.dart';
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase, SessionRecoveryStatus;

mixin ControllerAuthentication on ControllerState {
  @internal
  bool get internalCanEditLoginOptions =>
      !internalDisposed &&
      !internalIsSigningOut &&
      internalPhase != AppPhase.loggingIn &&
      internalPhase != AppPhase.checkingSession &&
      internalCredentialVault.isAvailable;

  @internal
  bool internalIsCurrentAuthentication(int generation) =>
      !internalDisposed && generation == internalLifecycleEpoch;

  @internal
  void internalReleaseLoginSecret() {
    internalLoginForm = internalLoginForm.copyWith(password: '', captcha: '');
  }

  @internal
  Future<void> internalInitializeController({
    UiError? previousLoginError,
  }) async {
    if (internalInitialized || internalDisposed || internalIsSigningOut) return;
    internalInitialized = true;
    if (internalLocalAccountStore != null &&
        !internalManualAuthenticationRequired &&
        await internalInitializeLocalHome())
      return;
    final formRevision = internalLoginFormRevision;
    final activity = internalBeginOperationTransition(
      ControllerActivityKind.initialization,
    );
    final generation = internalLifecycleEpoch;
    internalError = previousLoginError;
    internalSetPhase(AppPhase.checkingSession);
    try {
      if (internalNeedsManualLogin(formRevision)) return;
      if (internalBackend case final RouteSettingsBackend routeBackend) {
        final settings = await routeBackend.routeSettings();
        if (!internalIsCurrentAuthentication(generation)) return;
        internalApplyRouteSettings(settings);
        if (internalNeedsManualLogin(formRevision)) return;
      }
      final status = await internalBackend.authStatus();
      if (!internalIsCurrentAuthentication(generation)) return;
      if (internalNeedsManualLogin(formRevision)) return;
      if (status == AuthStatus.signedIn) {
        final user = await internalBackend.userInfo();
        if (!internalIsCurrentAuthentication(generation)) return;
        if (internalNeedsManualLogin(formRevision)) return;
        if (user != null) {
          internalError = null;
          internalUser = user;
          internalReleaseLoginSecret();
          internalSetPhase(AppPhase.home);
          if (internalIsCurrentAuthentication(generation))
            unawaited(internalAutomaticSchoolAction(internalRefreshHome));
          return;
        }
      }
      // 修订号在 controller 生命周期内保留：重建只能恢复尚未被用户
      // 改填、提交或退出的表单，不能重新授权已消费的自动登录尝试。
      if (internalCredentialRestoreAllowed &&
          internalLoginFormRevision == 0 &&
          internalCredentialVault.isAvailable) {
        final saved = await internalCredentialVault.read();
        if (!internalIsCurrentAuthentication(generation)) return;
        if (internalNeedsManualLogin(formRevision)) return;
        if (internalLoginFormRevision == formRevision &&
            internalCredentialVault.isAvailable &&
            saved != null &&
            saved.isUsable) {
          internalLoginForm = internalLoginForm.copyWith(
            username: saved.username,
            password: saved.password,
            autoLogin: saved.autoLogin,
            rememberPassword: true,
          );
          // 已授权的自动登录可将耗尽的验证码交给当前表单；完成、取消、
          // 账号变化和销毁都会释放密码，等待人工答案期间保留当前输入。
          if (saved.autoLogin) {
            if (internalBackend case final InteractiveLoginBackend backend) {
              await internalSubmitInteractiveLogin(backend);
            } else {
              await internalSubmitLoginController();
            }
            return;
          }
        }
      }
      internalSetPhase(AppPhase.login);
    } on Object catch (error, stackTrace) {
      if (!internalIsCurrentAuthentication(generation)) return;
      final failure = internalRecordFailure(
        error,
        DiagnosticOperation.initialization,
        stackTrace: stackTrace,
      );
      internalError = internalLoginFormRevision == formRevision
          ? previousLoginError ?? failure
          : failure;
      internalSetPhase(AppPhase.login);
    } finally {
      internalEndOperationTransition(activity);
    }
  }

  @internal
  bool internalNeedsManualLogin(int formRevision) {
    if (!internalManualAuthenticationRequired &&
        internalLoginFormRevision == formRevision) {
      return false;
    }
    // 明确退出或改填账号后，后台不能接受残留旧会话；手动认证成功才
    // 重新允许会话恢复。恢复在途出现新输入也必须交还给当前登录表单。
    internalUser = null;
    internalActiveRoutes = const <ConnectionMode>[];
    internalSetPhase(AppPhase.login);
    return true;
  }

  @internal
  Future<void> internalSubmitLoginController({
    bool preserveHome = false,
  }) async {
    if (internalDisposed ||
        internalIsSigningOut ||
        isLoggingIn ||
        internalSessionRecoveryFuture != null)
      return;
    final username = internalLoginForm.username.trim();
    if (username.isEmpty || internalLoginForm.password.isEmpty) {
      internalError = UbaaErrorMapper.fromCode(UbaaErrorCode.invalidInput);
      internalNotify();
      return;
    }
    internalCredentialRestoreAllowed = false;
    final input = LoginInput(
      username: username,
      password: internalLoginForm.password,
      captcha: internalLoginForm.captcha.trim().isEmpty
          ? null
          : internalLoginForm.captcha.trim(),
      rememberPassword: internalLoginForm.rememberPassword,
      autoLogin: internalLoginForm.autoLogin,
      routePolicy: internalLoginForm.routePolicy,
    );
    internalBeginAuthTelemetry();
    final inPlace = preserveHome && internalPhase == AppPhase.home;
    internalInPlaceLogin = inPlace;
    final ControllerActivity activity;
    if (inPlace) {
      // 认证使旧在途读取失效，但不销毁当前页面、筛选草稿和返回位置。
      activity = internalActivities.begin(
        ControllerActivityKind.authentication,
      );
      internalSessionLifecycle.invalidate();
      internalYgdkGeneration++;
      internalWriteCoordinator.invalidate();
    } else {
      activity = internalBeginOperationTransition(
        ControllerActivityKind.authentication,
      );
    }
    final epoch = internalLifecycleEpoch;
    bool current() => !internalDisposed && epoch == internalLifecycleEpoch;
    internalError = null;
    internalActiveRoutes = const <ConnectionMode>[];
    internalSessionRecoveryStatus = SessionRecoveryStatus.restoring;
    if (inPlace) {
      internalNotify();
    } else {
      internalSetPhase(AppPhase.loggingIn);
    }
    try {
      await internalLocalAccountStore?.signOut();
      if (!current()) return;
      await internalBackend.login(input);
      if (!current()) return;
      await internalRefreshRouteSettings();
      if (!current()) return;
      final profile = await internalBackend.userInfo();
      if (!current()) return;
      await internalCompleteAuthenticatedLogin(input, profile, epoch);
    } on Object catch (error, stackTrace) {
      if (!current()) return;
      if (error is BackendException &&
          error.code == UbaaErrorCode.invalidCredentials) {
        try {
          await internalMutateCredential(epoch, internalCredentialVault.clear);
        } on Object catch (clearError, clearStack) {
          internalRecordFailure(
            clearError,
            DiagnosticOperation.logout,
            stackTrace: clearStack,
          );
        }
        if (!current()) return;
      }
      internalError = internalRecordFailure(
        error,
        DiagnosticOperation.login,
        stackTrace: stackTrace,
      );
      internalEndAuthTelemetry(error: internalError, stackTrace: stackTrace);
      internalSessionRecoveryStatus = SessionRecoveryStatus.needsLogin;
      internalInPlaceLogin = false;
      internalReleaseLoginSecret();
      internalSetPhase(inPlace ? AppPhase.home : AppPhase.login);
    } finally {
      if (current()) {
        internalInPlaceLogin = false;
        internalReleaseLoginSecret();
      }
      internalEndOperationTransition(activity);
      internalNotify();
    }
  }

  @internal
  Future<void> internalMutateCredential(
    int epoch,
    Future<void> Function() action,
  ) async {
    final previous = internalCredentialMutation;
    final pending = () async {
      if (previous != null) {
        try {
          await previous;
        } on Object {
          /* 后续清除仍继续。 */
        }
      }
      if (!internalDisposed && epoch == internalLifecycleEpoch) await action();
    }();
    internalCredentialMutation = pending;
    try {
      await pending;
    } finally {
      if (identical(internalCredentialMutation, pending))
        internalCredentialMutation = null;
    }
  }
}

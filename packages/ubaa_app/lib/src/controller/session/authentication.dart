import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/routing.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
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
    internalBeginWriteTransition();
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
          await internalRecordAppOpen();
          if (internalIsCurrentAuthentication(generation))
            unawaited(refreshHome());
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
          // 手动恢复仅供遮罩表单使用；自动登录只尝试一次，成功或失败
          // 都释放表单中的密码，账号变化和销毁也会使本次恢复失效。
          if (saved.autoLogin) {
            await internalSubmitLoginController();
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
      internalEndWriteTransition();
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
    final inPlace = preserveHome && internalPhase == AppPhase.home;
    internalInPlaceLogin = inPlace;
    if (inPlace) {
      // 认证使旧在途读取失效，但不销毁当前页面、筛选草稿和返回位置。
      internalWriteTransitions++;
      internalLifecycleEpoch++;
      internalYgdkGeneration++;
      internalWriteCoordinator.invalidate();
    } else {
      internalBeginWriteTransition();
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
      internalSessionRecoveryStatus = SessionRecoveryStatus.needsLogin;
      internalSetPhase(inPlace ? AppPhase.home : AppPhase.login);
    } finally {
      internalInPlaceLogin = false;
      internalLoginForm = internalLoginForm.copyWith(password: '', captcha: '');
      internalEndWriteTransition();
      internalNotify();
    }
  }

  @internal
  Future<void> internalCompleteAuthenticatedLogin(
    LoginInput input,
    UserSummary? profile,
    int epoch,
  ) async {
    final username = input.username.trim();
    bool current() => !internalDisposed && epoch == internalLifecycleEpoch;
    if (internalLocalAccountStore != null && profile == null) {
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    if (internalLocalAccountStore != null &&
        profile != null &&
        profile.username != username &&
        profile.schoolId != username) {
      internalUser = null;
      internalResetFeatureSnapshots();
      internalSessionRecoveryStatus = SessionRecoveryStatus.needsLogin;
      internalError = UbaaErrorMapper.fromCode(
        UbaaErrorCode.authenticationRequired,
      );
      internalNotify();
      try {
        await internalLocalAccountStore!.signOut();
      } on Object catch (error, stackTrace) {
        internalError = internalRecordFailure(
          error,
          DiagnosticOperation.login,
          stackTrace: stackTrace,
        );
      }
      return;
    }
    if (internalLocalAccount != null &&
        internalLocalAccount!.username != username) {
      // 原位换账号不能让旧账号的内容继续挂在新身份下面。
      internalUser = null;
      internalResetFeatureSnapshots(advanceLifecycle: false);
      internalNotify();
      await internalLocalAccountStore?.signOut();
      if (!current()) return;
      await internalCloseOfflineAccount();
      if (!current()) return;
      internalLocalAccount = null;
    }
    internalUser = profile ?? UserSummary(username: username);
    try {
      if (input.rememberPassword && internalCredentialVault.isAvailable) {
        await internalMutateCredential(
          epoch,
          () => internalCredentialVault.write(
            Credential(
              username: username,
              password: input.password,
              autoLogin: input.autoLogin,
            ),
          ),
        );
      } else if (!input.rememberPassword) {
        await internalMutateCredential(epoch, internalCredentialVault.clear);
      }
    } on Object catch (error, stackTrace) {
      if (!current()) return;
      internalRecordFailure(
        error,
        DiagnosticOperation.login,
        stackTrace: stackTrace,
      );
      internalError = UiError(
        code: UbaaErrorCode.internalError,
        kind: UbaaErrorKind.internal,
        title: '本机登录材料未保存',
        message: input.rememberPassword
            ? '已登录，但账号密码未能保存，下次需要重新输入。'
            : '已登录，但之前保存的账号密码未能清除，请稍后重试。',
      );
    }
    if (!current()) return;
    await internalRetainCurrentAccount(
      username: username,
      retainSession: input.rememberPassword,
    );
    if (!current()) return;
    if (internalError == null) internalAutomaticCredentialBlocked = false;
    internalManualAuthenticationRequired = false;
    internalSessionRecoveryStatus = SessionRecoveryStatus.ready;
    internalSetPhase(AppPhase.home);
    unawaited(internalQueueProfileRefresh(force: true));
    await internalRecordAppOpen();
    if (current()) unawaited(refreshHome());
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

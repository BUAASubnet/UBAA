import 'dart:async';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import '../state/read_scope.dart';
import '../state/state.dart';
import '../state/types.dart';

/// 登录完成只由本模块提交终态；验证码清理不会撤销本模块的完成 token。
mixin ControllerAuthenticationCompletion on ControllerState {
  Object? _activeCompletion;

  @internal
  Future<void> internalCompleteAuthenticatedLogin(
    LoginInput input,
    UserSummary? profile,
    int epoch,
  ) async {
    final scope = internalCaptureSessionScope();
    if (!scope.isCurrent || scope.lifecycle != epoch) return;
    final token = Object();
    _activeCompletion = token;
    bool current() => identical(_activeCompletion, token) && scope.isCurrent;
    try {
      if (internalLocalAccountStore != null &&
          (profile == null ||
              (profile.username != input.username.trim() &&
                  profile.schoolId != input.username.trim()))) {
        // 身份拒绝独立于本机清理结果；先关闭 UI/写资格，再结束旧账号入口。
        _releaseCompletionLoading();
        internalError = internalRecordFailure(
          const BackendException(UbaaErrorCode.authenticationRequired),
          DiagnosticOperation.login,
        );
        await internalRejectMismatchedAccount();
        return;
      }
      await _acceptAuthenticatedLogin(input, profile, scope, current);
    } on Object catch (error, stackTrace) {
      if (!current()) return;
      internalError = internalRecordFailure(
        error,
        DiagnosticOperation.login,
        stackTrace: stackTrace,
      );
      internalSessionRecoveryStatus = SessionRecoveryStatus.needsLogin;
      internalManualAuthenticationRequired = true;
      internalActiveRoutes = const [];
      final preserveHome = internalInPlaceLogin && internalUser != null;
      _releaseCompletionLoading();
      internalSetPhase(preserveHome ? AppPhase.home : AppPhase.login);
    } finally {
      if (identical(_activeCompletion, token)) _activeCompletion = null;
    }
  }

  void _releaseCompletionLoading() {
    internalInteractiveInPlace = false;
    internalInPlaceLogin = false;
    internalReleaseLoginSecret();
  }

  Future<void> _acceptAuthenticatedLogin(
    LoginInput input,
    UserSummary? profile,
    SessionScope scope,
    bool Function() current,
  ) async {
    final username = input.username.trim();
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
          scope.lifecycle,
          () => internalCredentialVault.write(
            Credential(
              username: username,
              password: input.password,
              autoLogin: input.autoLogin,
            ),
          ),
        );
      } else if (!input.rememberPassword) {
        await internalMutateCredential(
          scope.lifecycle,
          internalCredentialVault.clear,
        );
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
    _releaseCompletionLoading();
    internalSetPhase(AppPhase.home);
    unawaited(internalQueueProfileRefresh(force: true));
    await internalRecordAppOpen();
    if (current()) unawaited(refreshHome());
  }
}

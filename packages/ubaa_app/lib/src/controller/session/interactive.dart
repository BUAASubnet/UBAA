import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/interactive_auth.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../state/state.dart' show ControllerState;
import '../state/types.dart'
    show AppPhase, LoginFormState, SessionRecoveryStatus;

mixin ControllerInteractiveAuthentication on ControllerState {
  @internal
  bool internalIsCurrentInteractiveGeneration(int generation) =>
      !internalDisposed &&
      !internalIsSigningOut &&
      generation == internalInteractiveGeneration;

  @internal
  void internalSetInteractivePhase(AppPhase phase) {
    if (internalInteractiveInPlace && phase != AppPhase.home) {
      internalInPlaceLogin = phase == AppPhase.loggingIn;
      internalNotify();
    } else {
      internalSetPhase(phase);
    }
  }

  @internal
  bool internalIsCurrentInteractive(
    InteractiveLoginBackend backend,
    int generation,
    int credentialRevision,
  ) =>
      internalIsCurrentInteractiveGeneration(generation) &&
      identical(backend, internalBackend) &&
      credentialRevision == internalLoginCredentialRevision &&
      internalInteractiveEngaged;

  @internal
  LoginInput internalInteractiveInput(LoginFormState form) => LoginInput(
    username: form.username.trim(),
    password: form.password,
    rememberPassword: form.rememberPassword,
    autoLogin: form.autoLogin,
    routePolicy: form.routePolicy,
  );

  @internal
  Future<void> internalSubmitInteractiveLogin(
    InteractiveLoginBackend backend,
  ) async {
    if (internalDisposed || internalIsSigningOut || isLoggingIn) return;
    final form = internalLoginForm;
    if (form.username.trim().isEmpty || form.password.isEmpty) {
      internalError = UbaaErrorMapper.fromCode(UbaaErrorCode.invalidInput);
      internalNotify();
      return;
    }
    final beginning = !internalInteractiveEngaged;
    if (!beginning && !(internalLoginVerification?.canSubmit ?? false)) return;
    if (beginning) {
      internalCredentialRestoreAllowed = false;
      internalManualAuthenticationRequired = true;
      internalInteractiveGeneration++;
      internalInteractiveEngaged = true;
      internalActiveRoutes = const <ConnectionMode>[];
      internalSessionRecoveryStatus = SessionRecoveryStatus.restoring;
    }
    final generation = internalInteractiveGeneration;
    final credentialRevision = internalLoginCredentialRevision;
    internalBeginWriteTransition();
    internalError = null;
    internalSetInteractivePhase(AppPhase.loggingIn);
    try {
      final result = beginning
          ? await backend.beginInteractiveLogin(internalInteractiveInput(form))
          : await backend.submitInteractiveLogin(
              internalInteractiveInput(form),
              <ConnectionMode, String>{
                for (final route in internalLoginVerification!.routes)
                  if (route.status ==
                          LoginRouteVerificationStatus.captchaRequired &&
                      route.hasUsableFrame &&
                      route.answer.trim().isNotEmpty)
                    route.route: route.answer.trim(),
              },
            );
      if (!internalIsCurrentInteractive(
        backend,
        generation,
        credentialRevision,
      )) {
        result.releaseFrames();
        return;
      }
      internalAdoptVerification(result);
      final preferred = switch (form.routePolicy) {
        RoutePolicy.direct => ConnectionMode.direct,
        RoutePolicy.webvpn => ConnectionMode.webvpn,
        RoutePolicy.auto => null,
      };
      if (result.readyRoutes.length == 2 ||
          (preferred != null && result.readyRoutes.contains(preferred))) {
        final route = preferred ?? ConnectionMode.direct;
        await internalFinishInteractiveLogin(backend, route, generation);
        return;
      }
      if (result.readyRoutes.isEmpty &&
          !result.hasCaptcha &&
          !result.canSubmit) {
        final failure = result.routes
            .map((route) => route.error)
            .whereType<UiError>()
            .firstOrNull;
        throw failure == null
            ? const BackendException(UbaaErrorCode.upstreamChanged)
            : BackendException.fromUi(failure);
      }
      internalSetInteractivePhase(AppPhase.login);
    } on Object catch (error, stackTrace) {
      if (!internalIsCurrentInteractive(
        backend,
        generation,
        credentialRevision,
      ))
        return;
      final failure = internalRecordFailure(
        error,
        DiagnosticOperation.login,
        stackTrace: stackTrace,
      );
      final hasRecoverableState =
          (internalLoginVerification?.hasCaptcha ?? false) ||
          (internalLoginVerification?.readyRoutes.isNotEmpty ?? false);
      if (!hasRecoverableState) {
        internalClearVerificationState();
        backend.cancelInteractiveLogin();
        internalReleaseLoginSecret();
        if (error is BackendException &&
            error.code == UbaaErrorCode.invalidCredentials) {
          try {
            await internalMutateCredential(
              internalLifecycleEpoch,
              internalCredentialVault.clear,
            );
          } on Object catch (clearError, clearStackTrace) {
            if (internalIsCurrentInteractiveGeneration(generation)) {
              internalRecordFailure(
                clearError,
                DiagnosticOperation.login,
                stackTrace: clearStackTrace,
              );
            }
          }
        }
      }
      if (!internalIsCurrentInteractiveGeneration(generation)) return;
      internalError = failure;
      internalSetInteractivePhase(AppPhase.login);
    } finally {
      internalEndWriteTransition();
    }
  }

  @internal
  void internalAdoptVerification(LoginVerificationState incoming) {
    final previous = internalLoginVerification;
    final routes = <LoginRouteVerification>[];
    for (final route in incoming.routes) {
      final old = previous?.forRoute(route.route);
      final unchanged =
          old != null &&
          old.revision == route.revision &&
          old.status == route.status &&
          route.hasUsableFrame;
      if (!identical(old?.frame, route.frame)) old?.frame?.release();
      if (!unchanged) {
        internalCaptchaTimers.remove(route.route)?.cancel();
        if (route.hasUsableFrame && route.validFor > Duration.zero) {
          final duration = route.validFor > const Duration(seconds: 120)
              ? const Duration(seconds: 120)
              : route.validFor;
          final revision = route.revision;
          internalCaptchaTimers[route.route] = Timer(duration, () {
            if (!internalDisposed &&
                internalLoginVerification?.forRoute(route.route)?.revision ==
                    revision) {
              internalExpireCaptcha(route.route);
            }
          });
        }
      }
      routes.add(unchanged ? route.withAnswer(old.answer) : route);
    }
    internalLoginVerification = LoginVerificationState(
      routes: routes,
      profile: incoming.profile,
    );
    internalActiveRoutes = List<ConnectionMode>.unmodifiable(
      incoming.readyRoutes,
    );
  }

  @internal
  void internalSetCaptchaAnswer(ConnectionMode route, String answer) {
    if (internalDisposed || isLoggingIn || !internalInteractiveEngaged) return;
    final current = internalLoginVerification;
    if (current == null || !(current.forRoute(route)?.hasUsableFrame ?? false))
      return;
    internalLoginVerification = LoginVerificationState(
      profile: current.profile,
      routes: <LoginRouteVerification>[
        for (final value in current.routes)
          value.route == route ? value.withAnswer(answer) : value,
      ],
    );
    internalError = null;
    internalNotify();
  }

  @internal
  void internalExpireCaptcha(ConnectionMode route, {bool refreshing = false}) {
    final current = internalLoginVerification;
    final old = current?.forRoute(route);
    if (current == null || old == null) return;
    internalCaptchaTimers.remove(route)?.cancel();
    old.frame?.release();
    if (internalBackend case final InteractiveLoginBackend backend) {
      backend.discardInteractiveCaptcha(route);
    }
    internalLoginVerification = LoginVerificationState(
      profile: current.profile,
      routes: <LoginRouteVerification>[
        for (final value in current.routes)
          value.route == route
              ? value.cleared(
                  refreshing: refreshing,
                  error: refreshing
                      ? null
                      : const UiError(
                          code: UbaaErrorCode.invalidInput,
                          title: '验证码已失效',
                          message: '请刷新验证码后重新输入。',
                        ),
                )
              : value,
      ],
    );
    internalNotify();
  }

  @internal
  Future<void> internalRefreshCaptcha(ConnectionMode route) async {
    final backend = internalBackend is InteractiveLoginBackend
        ? internalBackend as InteractiveLoginBackend
        : null;
    if (backend == null ||
        internalDisposed ||
        !internalInteractiveEngaged ||
        isLoggingIn ||
        internalLoginVerification?.forRoute(route)?.status !=
            LoginRouteVerificationStatus.captchaRequired)
      return;
    final generation = internalInteractiveGeneration;
    final credentialRevision = internalLoginCredentialRevision;
    internalExpireCaptcha(route, refreshing: true);
    internalBeginWriteTransition();
    internalSetInteractivePhase(AppPhase.loggingIn);
    try {
      final result = await backend.refreshInteractiveCaptcha(route);
      if (!internalIsCurrentInteractive(
        backend,
        generation,
        credentialRevision,
      )) {
        result.releaseFrames();
        return;
      }
      internalAdoptVerification(result);
      internalError = null;
    } on Object catch (error, stackTrace) {
      if (!internalIsCurrentInteractive(
        backend,
        generation,
        credentialRevision,
      ))
        return;
      internalError = internalRecordFailure(
        error,
        DiagnosticOperation.login,
        stackTrace: stackTrace,
      );
      internalExpireCaptcha(route);
    } finally {
      if (internalIsCurrentInteractive(backend, generation, credentialRevision))
        internalSetInteractivePhase(AppPhase.login);
      internalEndWriteTransition();
    }
  }

  @internal
  Future<void> internalContinueReadyLogin(
    ConnectionMode route, {
    bool pinRoute = false,
  }) async {
    final backend = internalBackend is InteractiveLoginBackend
        ? internalBackend as InteractiveLoginBackend
        : null;
    if (backend == null ||
        internalDisposed ||
        internalIsSigningOut ||
        !internalInteractiveEngaged ||
        isLoggingIn ||
        !(internalLoginVerification?.readyRoutes.contains(route) ?? false))
      return;
    final generation = internalInteractiveGeneration;
    final credentialRevision = internalLoginCredentialRevision;
    internalBeginWriteTransition();
    internalError = null;
    internalSetInteractivePhase(AppPhase.loggingIn);
    try {
      await internalFinishInteractiveLogin(
        backend,
        route,
        generation,
        pinRoute: pinRoute,
      );
    } on Object catch (error, stackTrace) {
      if (!internalIsCurrentInteractive(
        backend,
        generation,
        credentialRevision,
      ))
        return;
      internalError = internalRecordFailure(
        error,
        DiagnosticOperation.login,
        stackTrace: stackTrace,
      );
      if (!pinRoute &&
          internalLoginForm.routePolicy == RoutePolicy.auto &&
          internalError?.code == UbaaErrorCode.authenticationRequired) {
        final failure = internalError!;
        internalError = UiError(
          code: failure.code,
          kind: failure.kind,
          retryable: failure.retryable,
          issueId: failure.issueId,
          resolvedRoute: failure.resolvedRoute,
          title: '自动连接暂未就绪',
          message: '可完成另一条路线的验证，或选择“改用${route.label}并继续”。',
        );
      }
      internalSetInteractivePhase(AppPhase.login);
    } finally {
      internalEndWriteTransition();
    }
  }

  @internal
  Future<void> internalFinishInteractiveLogin(
    InteractiveLoginBackend backend,
    ConnectionMode route,
    int generation, {
    bool pinRoute = false,
  }) async {
    // 每次最终继续都读取当前表单；等待验证码前捕获的选项不能重新授权保存。
    final form = internalLoginForm;
    final revision = internalLoginCredentialRevision;
    final completion = await backend.continueInteractiveLogin(
      route,
      pinRoute: pinRoute,
    );
    if (!internalIsCurrentInteractive(backend, generation, revision)) return;
    internalClearVerificationState();
    internalReleaseLoginSecret();
    internalApplyRouteSettings(completion.settings);
    await internalCompleteAuthenticatedLogin(
      internalInteractiveInput(form),
      completion.user,
      internalLifecycleEpoch,
    );
  }

  @internal
  void internalClearVerificationState() {
    for (final timer in internalCaptchaTimers.values) {
      timer.cancel();
    }
    internalCaptchaTimers.clear();
    internalLoginVerification?.releaseFrames();
    internalLoginVerification = null;
    internalInteractiveEngaged = false;
  }

  @internal
  void internalCancelLoginVerification({
    bool releasePassword = true,
    bool notify = true,
  }) {
    if (!internalInteractiveEngaged && internalLoginVerification == null)
      return;
    internalInteractiveGeneration++;
    internalClearVerificationState();
    if (internalBackend case final InteractiveLoginBackend backend) {
      backend.cancelInteractiveLogin();
    }
    internalManualAuthenticationRequired = true;
    internalCredentialRestoreAllowed = false;
    if (releasePassword) internalReleaseLoginSecret();
    internalActiveRoutes = const <ConnectionMode>[];
    if (internalPhase == AppPhase.loggingIn) internalPhase = AppPhase.login;
    if (internalInteractiveInPlace) {
      internalPhase = AppPhase.home;
      internalSessionRecoveryStatus = SessionRecoveryStatus.needsLogin;
    }
    internalInteractiveInPlace = false;
    internalInPlaceLogin = false;
    if (notify) internalNotify();
  }
}

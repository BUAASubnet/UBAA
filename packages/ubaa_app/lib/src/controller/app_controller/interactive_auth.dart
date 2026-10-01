part of '../app_controller.dart';

extension _AppControllerInteractiveAuthentication on AppController {
  bool _isCurrentInteractiveGeneration(int generation) =>
      !_disposed && !_isSigningOut && generation == _interactiveGeneration;

  void _setInteractivePhase(AppPhase phase) {
    if (_interactiveInPlace && phase != AppPhase.home) {
      _inPlaceLogin = phase == AppPhase.loggingIn;
      _notify();
    } else {
      _setPhase(phase);
    }
  }

  bool _isCurrentInteractive(
    InteractiveLoginBackend backend,
    int generation,
    int credentialRevision,
  ) =>
      _isCurrentInteractiveGeneration(generation) &&
      identical(backend, _backend) &&
      credentialRevision == _loginCredentialRevision &&
      _interactiveEngaged;

  LoginInput _interactiveInput(LoginFormState form) => LoginInput(
    username: form.username.trim(),
    password: form.password,
    rememberPassword: form.rememberPassword,
    autoLogin: form.autoLogin,
    routePolicy: form.routePolicy,
  );

  Future<void> _submitInteractiveLogin(InteractiveLoginBackend backend) async {
    if (_disposed || _isSigningOut || isLoggingIn) return;
    final form = _loginForm;
    if (form.username.trim().isEmpty || form.password.isEmpty) {
      _error = UbaaErrorMapper.fromCode(UbaaErrorCode.invalidInput);
      _notify();
      return;
    }
    final beginning = !_interactiveEngaged;
    if (!beginning && !(_loginVerification?.canSubmit ?? false)) return;
    if (beginning) {
      _credentialRestoreAllowed = false;
      _manualAuthenticationRequired = true;
      _interactiveGeneration++;
      _interactiveEngaged = true;
      _activeRoutes = const <ConnectionMode>[];
      _sessionRecoveryStatus = SessionRecoveryStatus.restoring;
    }
    final generation = _interactiveGeneration;
    final credentialRevision = _loginCredentialRevision;
    _beginWriteTransition();
    _error = null;
    _setInteractivePhase(AppPhase.loggingIn);
    try {
      final result = beginning
          ? await backend.beginInteractiveLogin(_interactiveInput(form))
          : await backend.submitInteractiveLogin(
              _interactiveInput(form),
              <ConnectionMode, String>{
                for (final route in _loginVerification!.routes)
                  if (route.status ==
                          LoginRouteVerificationStatus.captchaRequired &&
                      route.hasUsableFrame &&
                      route.answer.trim().isNotEmpty)
                    route.route: route.answer.trim(),
              },
            );
      if (!_isCurrentInteractive(backend, generation, credentialRevision)) {
        result.releaseFrames();
        return;
      }
      _adoptVerification(result);
      final preferred = switch (form.routePolicy) {
        RoutePolicy.direct => ConnectionMode.direct,
        RoutePolicy.webvpn => ConnectionMode.webvpn,
        RoutePolicy.auto => null,
      };
      if (result.readyRoutes.length == 2 ||
          (preferred != null && result.readyRoutes.contains(preferred))) {
        final route = preferred ?? ConnectionMode.direct;
        await _finishInteractiveLogin(backend, route, generation);
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
      _setInteractivePhase(AppPhase.login);
    } on Object catch (error, stackTrace) {
      if (!_isCurrentInteractive(backend, generation, credentialRevision))
        return;
      final failure = _recordFailure(
        error,
        DiagnosticOperation.login,
        stackTrace: stackTrace,
      );
      final hasRecoverableState =
          (_loginVerification?.hasCaptcha ?? false) ||
          (_loginVerification?.readyRoutes.isNotEmpty ?? false);
      if (!hasRecoverableState) {
        _clearVerificationState();
        backend.cancelInteractiveLogin();
        _releaseLoginSecret();
        if (error is BackendException &&
            error.code == UbaaErrorCode.invalidCredentials) {
          try {
            await _mutateCredential(_lifecycleEpoch, _credentialVault.clear);
          } on Object catch (clearError, clearStackTrace) {
            if (_isCurrentInteractiveGeneration(generation)) {
              _recordFailure(
                clearError,
                DiagnosticOperation.login,
                stackTrace: clearStackTrace,
              );
            }
          }
        }
      }
      if (!_isCurrentInteractiveGeneration(generation)) return;
      _error = failure;
      _setInteractivePhase(AppPhase.login);
    } finally {
      _endWriteTransition();
    }
  }

  void _adoptVerification(LoginVerificationState incoming) {
    final previous = _loginVerification;
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
        _captchaTimers.remove(route.route)?.cancel();
        if (route.hasUsableFrame && route.validFor > Duration.zero) {
          final duration = route.validFor > const Duration(seconds: 120)
              ? const Duration(seconds: 120)
              : route.validFor;
          final revision = route.revision;
          _captchaTimers[route.route] = Timer(duration, () {
            if (!_disposed &&
                _loginVerification?.forRoute(route.route)?.revision ==
                    revision) {
              _expireCaptcha(route.route);
            }
          });
        }
      }
      routes.add(unchanged ? route.withAnswer(old.answer) : route);
    }
    _loginVerification = LoginVerificationState(
      routes: routes,
      profile: incoming.profile,
    );
    _activeRoutes = List<ConnectionMode>.unmodifiable(incoming.readyRoutes);
  }

  void _setCaptchaAnswer(ConnectionMode route, String answer) {
    if (_disposed || isLoggingIn || !_interactiveEngaged) return;
    final current = _loginVerification;
    if (current == null || !(current.forRoute(route)?.hasUsableFrame ?? false))
      return;
    _loginVerification = LoginVerificationState(
      profile: current.profile,
      routes: <LoginRouteVerification>[
        for (final value in current.routes)
          value.route == route ? value.withAnswer(answer) : value,
      ],
    );
    _error = null;
    _notify();
  }

  void _expireCaptcha(ConnectionMode route, {bool refreshing = false}) {
    final current = _loginVerification;
    final old = current?.forRoute(route);
    if (current == null || old == null) return;
    _captchaTimers.remove(route)?.cancel();
    old.frame?.release();
    if (_backend case final InteractiveLoginBackend backend) {
      backend.discardInteractiveCaptcha(route);
    }
    _loginVerification = LoginVerificationState(
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
    _notify();
  }

  Future<void> _refreshCaptcha(ConnectionMode route) async {
    final backend = _backend is InteractiveLoginBackend
        ? _backend as InteractiveLoginBackend
        : null;
    if (backend == null ||
        _disposed ||
        !_interactiveEngaged ||
        isLoggingIn ||
        _loginVerification?.forRoute(route)?.status !=
            LoginRouteVerificationStatus.captchaRequired)
      return;
    final generation = _interactiveGeneration;
    final credentialRevision = _loginCredentialRevision;
    _expireCaptcha(route, refreshing: true);
    _beginWriteTransition();
    _setInteractivePhase(AppPhase.loggingIn);
    try {
      final result = await backend.refreshInteractiveCaptcha(route);
      if (!_isCurrentInteractive(backend, generation, credentialRevision)) {
        result.releaseFrames();
        return;
      }
      _adoptVerification(result);
      _error = null;
    } on Object catch (error, stackTrace) {
      if (!_isCurrentInteractive(backend, generation, credentialRevision))
        return;
      _error = _recordFailure(
        error,
        DiagnosticOperation.login,
        stackTrace: stackTrace,
      );
      _expireCaptcha(route);
    } finally {
      if (_isCurrentInteractive(backend, generation, credentialRevision))
        _setInteractivePhase(AppPhase.login);
      _endWriteTransition();
    }
  }

  Future<void> _continueReadyLogin(
    ConnectionMode route, {
    bool pinRoute = false,
  }) async {
    final backend = _backend is InteractiveLoginBackend
        ? _backend as InteractiveLoginBackend
        : null;
    if (backend == null ||
        _disposed ||
        _isSigningOut ||
        !_interactiveEngaged ||
        isLoggingIn ||
        !(_loginVerification?.readyRoutes.contains(route) ?? false))
      return;
    final generation = _interactiveGeneration;
    final credentialRevision = _loginCredentialRevision;
    _beginWriteTransition();
    _error = null;
    _setInteractivePhase(AppPhase.loggingIn);
    try {
      await _finishInteractiveLogin(
        backend,
        route,
        generation,
        pinRoute: pinRoute,
      );
    } on Object catch (error, stackTrace) {
      if (!_isCurrentInteractive(backend, generation, credentialRevision))
        return;
      _error = _recordFailure(
        error,
        DiagnosticOperation.login,
        stackTrace: stackTrace,
      );
      if (!pinRoute &&
          _loginForm.routePolicy == RoutePolicy.auto &&
          _error?.code == UbaaErrorCode.authenticationRequired) {
        final failure = _error!;
        _error = UiError(
          code: failure.code,
          kind: failure.kind,
          retryable: failure.retryable,
          issueId: failure.issueId,
          resolvedRoute: failure.resolvedRoute,
          title: '自动连接暂未就绪',
          message: '可完成另一条路线的验证，或选择“改用${route.label}并继续”。',
        );
      }
      _setInteractivePhase(AppPhase.login);
    } finally {
      _endWriteTransition();
    }
  }

  Future<void> _finishInteractiveLogin(
    InteractiveLoginBackend backend,
    ConnectionMode route,
    int generation, {
    bool pinRoute = false,
  }) async {
    // 每次最终继续都读取当前表单；等待验证码前捕获的选项不能重新授权保存。
    final form = _loginForm;
    final revision = _loginCredentialRevision;
    final completion = await backend.continueInteractiveLogin(
      route,
      pinRoute: pinRoute,
    );
    if (!_isCurrentInteractive(backend, generation, revision)) return;
    _clearVerificationState();
    _releaseLoginSecret();
    _applyRouteSettings(completion.settings);
    await _completeAuthenticatedLogin(
      _interactiveInput(form),
      completion.user,
      _lifecycleEpoch,
    );
    _interactiveInPlace = false;
    _inPlaceLogin = false;
  }

  void _clearVerificationState() {
    for (final timer in _captchaTimers.values) {
      timer.cancel();
    }
    _captchaTimers.clear();
    _loginVerification?.releaseFrames();
    _loginVerification = null;
    _interactiveEngaged = false;
  }

  void _cancelLoginVerification({
    bool releasePassword = true,
    bool notify = true,
  }) {
    if (!_interactiveEngaged && _loginVerification == null) return;
    _interactiveGeneration++;
    _clearVerificationState();
    if (_backend case final InteractiveLoginBackend backend) {
      backend.cancelInteractiveLogin();
    }
    _manualAuthenticationRequired = true;
    _credentialRestoreAllowed = false;
    if (releasePassword) _releaseLoginSecret();
    _activeRoutes = const <ConnectionMode>[];
    if (_phase == AppPhase.loggingIn) _phase = AppPhase.login;
    if (_interactiveInPlace) {
      _phase = AppPhase.home;
      _sessionRecoveryStatus = SessionRecoveryStatus.needsLogin;
    }
    _interactiveInPlace = false;
    _inPlaceLogin = false;
    if (notify) _notify();
  }
}

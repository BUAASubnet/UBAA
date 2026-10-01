part of '../app_controller.dart';

extension _AppControllerSettings on AppController {
  Future<void> _setRoutePolicyController(RoutePolicy value) async {
    if (_disposed || isLoggingIn || _isSigningOut) return;
    final previousPolicy = _loginForm.routePolicy;
    if (previousPolicy == value && !_routePolicyInFlight) return;
    _cancelLoginVerification(releasePassword: false, notify: false);
    final backend = _backend;
    final credentials = _loginCredentialRevision;
    final request = ++_routePolicyGeneration;
    _routePolicyInFlight = true;
    _beginWriteTransition();
    final epoch = _lifecycleEpoch;
    bool isCurrent() =>
        !_disposed &&
        !_isSigningOut &&
        identical(backend, _backend) &&
        epoch == _lifecycleEpoch &&
        credentials == _loginCredentialRevision &&
        request == _routePolicyGeneration;
    _clearError();
    try {
      await backend.prepareLogin(value);
      if (!isCurrent()) return;
      BackendRouteSettings? settings;
      if (backend case final RouteSettingsBackend routeBackend) {
        settings = await routeBackend.routeSettings();
        if (!isCurrent()) return;
      }
      if (settings case final routeSettings?) {
        _applyRouteSettings(routeSettings);
      } else {
        _loginForm = _loginForm.copyWith(routePolicy: value);
      }
      if (_phase == AppPhase.home &&
          settings != null &&
          !_routePolicyHasSession(value, settings.activeRoutes)) {
        // 切换到尚未认证的固定路线时，不能继续展示旧用户数据；保留用户名和
        // 用户主动保存的凭据，回到登录页完成目标路线认证。
        _user = null;
        _resetFeatureSnapshots();
        _setPhase(AppPhase.login);
      }
    } on BackendException catch (exception, stackTrace) {
      if (!isCurrent()) return;
      _loginForm = _loginForm.copyWith(routePolicy: previousPolicy);
      _error = _recordFailure(
        exception,
        DiagnosticOperation.routeChange,
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      if (!isCurrent()) return;
      _loginForm = _loginForm.copyWith(routePolicy: previousPolicy);
      _error = _recordFailure(
        error,
        DiagnosticOperation.routeChange,
        stackTrace: stackTrace,
      );
    } finally {
      if (request == _routePolicyGeneration) _routePolicyInFlight = false;
      _endWriteTransition();
    }
    _notify();
    unawaited(_queueProfileRefresh(force: true));
  }

  Future<void> _setTelemetryEnabledController(bool value) async {
    // Noop不能把本地布尔值当作统计已开启；可用客户端仍在调用边界开关。
    _telemetryEnabled = value && telemetryAvailable;
    if (!value) await _flushTelemetry();
    _notify();
  }
}

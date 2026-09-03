part of 'ubaa_app_host.dart';

extension _UbaaAppHostCallbacks on _UbaaAppHostState {
  PlatformPhotoPicker? get _photoPicker {
    final picker = widget.photoPicker;
    if (picker == null) return null;
    return PermissionedPhotoPicker(
      permissions:
          widget.permissionGateway ?? const UnavailablePermissionGateway(),
      picker: picker,
    );
  }

  Widget _buildApplication() => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => MaterialApp(
      title: 'UBAA',
      debugShowCheckedModeBanner: false,
      theme: UbaaTheme.light(),
      darkTheme: UbaaTheme.dark(),
      themeMode: ThemeMode.system,
      home: _buildHome(),
    ),
  );

  Widget _buildHome() => switch (_controller.phase) {
    AppPhase.splash || AppPhase.checkingSession => const UbaaSplashView(),
    AppPhase.login || AppPhase.loggingIn => UbaaLoginView(
      username: _controller.loginForm.username,
      password: _controller.loginForm.password,
      captcha: _controller.loginForm.captcha,
      rememberPassword: _controller.loginForm.rememberPassword,
      autoLogin: _controller.loginForm.autoLogin,
      routePolicy: _controller.loginForm.routePolicy,
      error: _controller.error,
      isLoading: _controller.phase == AppPhase.loggingIn,
      credentialPersistenceAvailable:
          _controller.credentialPersistenceAvailable,
      onUsernameChanged: _controller.setUsername,
      onPasswordChanged: _controller.setPassword,
      onCaptchaChanged: _controller.setCaptcha,
      onRememberPasswordChanged: _controller.setRememberPassword,
      onAutoLoginChanged: _controller.setAutoLogin,
      onRoutePolicyChanged: (value) {
        unawaited(_controller.setRoutePolicy(value));
      },
      onSubmit: () => unawaited(_controller.submitLogin()),
    ),
    AppPhase.home => UbaaMainShell(
      user: _controller.user,
      snapshots: _controller.snapshots,
      routePolicy: _controller.loginForm.routePolicy,
      activeRoutes: _controller.activeRoutes,
      initialTab: widget.initialTab,
      telemetryEnabled: _controller.telemetryEnabled,
      onRefresh: _controller.refreshHome,
      onRetryFeature: _controller.retryFeature,
      onFeatureQuery: (feature, query) {
        return _controller.refreshFeatureQuery(feature, query);
      },
      onPrepareBykcWrite: (operation, courseId) =>
          _controller.prepareBykcWrite(operation, courseId),
      onPrepareBykcSignWrite: _controller.prepareBykcSignWrite,
      onPrepareSigninWrite: _controller.prepareSigninWrite,
      onPrepareCancellationWrite: (operation, targetId) =>
          _controller.prepareCancellationWrite(operation, targetId),
      onPrepareLibbookReserveWrite:
          ({
            required areaId,
            required seatId,
            required day,
            required segment,
            required startTime,
            required endTime,
          }) => _controller.prepareLibbookReserveWrite(
            areaId: areaId,
            seatId: seatId,
            day: day,
            segment: segment,
            startTime: startTime,
            endTime: endTime,
          ),
      onPrepareCgyySubmitWrite: _controller.prepareCgyySubmitWrite,
      onPrepareYgdkSubmitWrite: _controller.prepareYgdkWrite,
      onPickYgdkPhoto: _photoPicker?.pickPhoto,
      onPrepareEvaluationWrite: _controller.prepareEvaluationWrite,
      onCommitWrite: _controller.commitWrite,
      onWriteSuccess: _controller.refreshAfterWrite,
      onVerifyCgyyReceipt: _controller.matchesCgyyReceipt,
      onLogout: _controller.logout,
      onLogoutAndClearAccount: () =>
          _controller.logout(clearSavedCredential: true),
      onRoutePolicyChanged: (value) {
        unawaited(_controller.setRoutePolicy(value));
      },
      onTelemetryChanged: (value) {
        unawaited(_controller.setTelemetryEnabled(value));
      },
    ),
  };
}

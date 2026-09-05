part of 'ubaa_app_host.dart';

extension _UbaaAppHostCallbacks on _UbaaAppHostState {
  PlatformPhotoPicker? get _photoPicker {
    final picker = widget.photoPicker;
    final permissions = widget.permissionGateway;
    if (picker == null || !picker.isAvailable || permissions == null) {
      return null;
    }
    return PermissionedPhotoPicker(permissions: permissions, picker: picker);
  }

  PlatformLocationProvider get _locationProvider =>
      PermissionedLocationProvider(
        permissions:
            widget.permissionGateway ?? const UnavailablePermissionGateway(),
        provider:
            widget.locationProvider ?? const UnavailableLocationProvider(),
      );

  Future<WriteIntent> _prepareBykcSignWrite(BykcSignAction action) async {
    final coordinator = _controller.writeCoordinator;
    final coordinated = coordinator.state.phase == WritePhase.preparing;
    PlatformLocation? location;
    if (action.requiresCoordinates) {
      location = await _locationProvider.currentLocation();
    }
    if (!identical(_controller.writeCoordinator, coordinator) ||
        (coordinated && coordinator.state.phase != WritePhase.preparing)) {
      throw UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict);
    }
    return _controller.prepareBykcSignWrite(
      action.courseId,
      action.signType,
      lat: location?.lat,
      lng: location?.lng,
    );
  }

  Future<WriteCommitResult> _commitWrite(String intentId) async {
    try {
      return await _controller.commitWrite(intentId);
    } on BackendException catch (exception) {
      throw UbaaErrorMapper.fromCode(exception.code);
    } on Object {
      throw UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
    }
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
    AppPhase.home => _buildMainShell(),
  };

  Widget _buildMainShell() {
    final photoPicker = _photoPicker;
    final hasYgdkSubmissionCapabilities =
        _controller.hasYgdkSubmissionBackendCapabilities && photoPicker != null;
    final hasEvaluationSubmissionCapabilities =
        _controller.hasEvaluationSubmissionBackendCapabilities;
    return UbaaMainShell(
      user: _controller.user,
      snapshots: _controller.snapshots,
      routePolicy: _controller.loginForm.routePolicy,
      activeRoutes: _controller.activeRoutes,
      writeState: _controller.writeCoordinator.state,
      onRunWritePrepare: _controller.writeCoordinator.prepareForUi,
      onCancelWrite: _controller.writeCoordinator.cancelForUi,
      onConfirmWrite: _controller.writeCoordinator.confirmForUi,
      initialTab: widget.initialTab,
      telemetryEnabled: _controller.telemetryEnabled,
      onRefresh: _controller.refreshHome,
      onRetryFeature: _controller.retryFeature,
      onFeatureQuery: (feature, query) {
        return _controller.refreshFeatureQuery(feature, query);
      },
      onPrepareBykcWrite: (operation, courseId) =>
          _controller.prepareBykcWrite(operation, courseId),
      onPrepareBykcSignWrite: _prepareBykcSignWrite,
      onPrepareSigninWrite: _controller.prepareSigninWrite,
      onPrepareCgyyCancelWrite: _controller.prepareCgyyCancelWrite,
      onPrepareLibbookReserveWrite: _controller.prepareLibbookReserveWrite,
      onPrepareLibbookCancelWrite: _controller.prepareLibbookCancelWrite,
      onPrepareCgyySubmitWrite: _controller.prepareCgyySubmitWrite,
      onPrepareYgdkSubmitWrite: hasYgdkSubmissionCapabilities
          ? _controller.prepareYgdkWrite
          : null,
      onPickYgdkPhoto: hasYgdkSubmissionCapabilities
          ? photoPicker.pickPhoto
          : null,
      onPrepareEvaluationWrite: hasEvaluationSubmissionCapabilities
          ? _controller.prepareEvaluationWrite
          : null,
      onDiscardWriteIntent: _controller.discardWriteIntent,
      onCommitWrite: _commitWrite,
      onWriteSuccess: (operation, readbackQuery) =>
          _controller.refreshAfterWrite(operation, readbackQuery),
      onVerifyCgyyReceipt: _controller.matchesCgyyReceipt,
      onVerifyCgyyCancellation: _controller.verifyCgyyCancellation,
      onRefreshEvaluationAfterWrite: hasEvaluationSubmissionCapabilities
          ? _controller.refreshEvaluationAfterWrite
          : null,
      onRefreshYgdkAfterWrite: hasYgdkSubmissionCapabilities
          ? _controller.refreshYgdkAfterWrite
          : null,
      onLogout: _controller.logout,
      onLogoutAndClearAccount: () =>
          _controller.logout(clearSavedCredential: true),
      onRoutePolicyChanged: (value) {
        unawaited(_controller.setRoutePolicy(value));
      },
      onTelemetryChanged: (value) {
        unawaited(_controller.setTelemetryEnabled(value));
      },
    );
  }
}

part of 'ubaa_app_host.dart';

extension _UbaaAppHostCallbacks on _UbaaAppHostState {
  PermissionedPhotoPicker? get _photoPicker {
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
      throw UbaaErrorMapper.fromException(exception);
    } on Object {
      throw UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
    }
  }

  Widget _buildApplication() => AnimatedBuilder(
    animation: Listenable.merge([_controller, _gradeWatch]),
    builder: (context, _) => MaterialApp(
      title: 'UBAA',
      scaffoldMessengerKey: _messengerKey,
      locale: UbaaTheme.locale,
      supportedLocales: UbaaTheme.supportedLocales,
      localizationsDelegates: UbaaTheme.localizationsDelegates,
      debugShowCheckedModeBanner: false,
      theme: UbaaTheme.light(),
      darkTheme: UbaaTheme.dark(),
      themeMode: _themeMode,
      home: _buildHome(),
    ),
  );

  Widget _buildHome() => switch (_controller.phase) {
    AppPhase.splash || AppPhase.checkingSession => const UbaaSplashView(),
    AppPhase.login || AppPhase.loggingIn => _buildLoginView(),
    AppPhase.home => _buildMainShell(),
  };

  String? get _connectionStatus {
    if (!_controller.usesLocalRecovery) return null;
    return switch (_controller.sessionRecoveryStatus) {
      SessionRecoveryStatus.idle ||
      SessionRecoveryStatus.restoring => '正在连接，稍后更新内容',
      SessionRecoveryStatus.needsLogin => '需要登录，当前页面会保留',
      SessionRecoveryStatus.unavailable => '暂时无法更新，请稍后重试',
      SessionRecoveryStatus.ready =>
        _controller.localCacheError == null ? null : '当前内容可在线查看，本机保存暂不可用',
      SessionRecoveryStatus.signedOut => null,
    };
  }

  Widget _buildMainShell() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) _controller.onHomeFirstFrame();
    });
    final photoPicker = _photoPicker;
    final hasYgdkSubmissionCapabilities =
        _controller.hasYgdkSubmissionBackendCapabilities && photoPicker != null;
    final hasEvaluationSubmissionCapabilities =
        _controller.hasEvaluationSubmissionBackendCapabilities;
    final localOwner = _controller.localDataOwnerScope;
    final appInformation = widget.appInformation ?? SystemAppInformation();
    return UbaaMainShell(
      ihomeService: _controller.ihomeService,
      connectionStatus: _connectionStatus,
      writeReadbacks: _controller.writeReadbacks,
      writeReadbackError: _controller.writeReadbackError,
      onRefreshWriteReadbacks: _controller.refreshWriteReadbacks,
      onDismissWriteReadback: _controller.canClearBusinessCache
          ? _controller.dismissWriteReadback
          : null,
      onReconnect: () => unawaited(_controller.recoverSession()),
      onCompleteLogin:
          _controller.sessionRecoveryStatus == SessionRecoveryStatus.needsLogin
          ? _showInPlaceLogin
          : null,
      onLoadAppVersion: appInformation.version,
      onOpenAppLink: appInformation.open,
      readCacheEpoch: _controller.readCacheEpoch,
      businessCacheEpoch: _controller.businessCacheEpoch,
      cacheAccountId: _controller.cacheAccountId,
      canClearBusinessCache: _controller.canClearBusinessCache,
      onReadCacheUsage: (id) => _controller.cacheUsage(accountId: id),
      onClearBusinessCache: _clearCacheAndWidgets,
      onLoadAcademicTerms: (forceRefresh) =>
          _controller.loadAcademicTerms(forceRefresh: forceRefresh),
      scheduleImports: _controller.scheduleImports,
      onSaveScheduleSemester: _controller.canSaveScheduleSemester
          ? _controller.saveScheduleSemester
          : null,
      onCancelScheduleImport: _controller.cancelScheduleImport,
      onLoadAcademicWeeks: (term, forceRefresh) =>
          _controller.loadAcademicWeeks(term, forceRefresh: forceRefresh),
      onLoadCgyyPurposes: (force) =>
          _controller.loadCgyyPurposes(forceRefresh: force),
      onLoadAllGrades: (forceRefresh, onProgress) => _controller.loadAllGrades(
        forceRefresh: forceRefresh,
        onProgress: onProgress,
      ),
      gradeScoreNotice: _gradeWatch.notice,
      gradeCheckRoute: _gradeWatch.checkedRoute,
      onCheckGradeUpdates: _gradeWatch.check,
      onConsumeGradeNotice: _gradeWatch.consumeNotice,
      themeMode: _themeMode,
      onThemeModeChanged: _setThemeMode,
      user: _controller.displayUser,
      snapshots: _controller.snapshots,
      homeSnapshots: _controller.homeSnapshots,
      onLoadHomeDaySchedule: (date, force) =>
          _controller.loadHomeDaySchedule(date, forceRefresh: force),
      onLoadHomeSupplement: (source, force) =>
          _controller.loadHomeSupplement(source, forceRefresh: force),
      onLoadYgdkReminder: localOwner.accountKey.isEmpty
          ? null
          : () => _readReminder(localOwner),
      onSaveYgdkReminder: localOwner.accountKey.isEmpty
          ? null
          : (value) => _saveReminder(localOwner, value),
      onLoadBykcFilters: localOwner.accountKey.isEmpty
          ? null
          : () => _readBykcFilters(localOwner),
      onSaveBykcFilters: localOwner.accountKey.isEmpty
          ? null
          : (value) => _saveBykcFilters(localOwner, value),
      onLoadRecentFeatures: localOwner.accountKey.isEmpty
          ? null
          : () => _readRecentFeatures(localOwner),
      onSaveRecentFeatures: localOwner.accountKey.isEmpty
          ? null
          : (value) => _saveRecentFeatures(localOwner, value),
      ygdkRecordsReadback: _controller.ygdkReadbackState.records,
      routePolicy: _controller.loginForm.routePolicy,
      activeRoutes: _controller.activeRoutes,
      onReadDiagnostics: _controller.exportDiagnostics,
      writeState: _controller.writeCoordinator.state,
      onRunWritePrepare: _controller.writeCoordinator.prepareForUi,
      onCancelWrite: _controller.writeCoordinator.cancelForUi,
      onConfirmWrite: _controller.writeCoordinator.confirmForUi,
      initialDestination: widget.initialDestination,
      telemetryEnabled: _controller.telemetryEnabled,
      telemetryAvailable: _controller.telemetryAvailable,
      onRefresh: _controller.refreshHome,
      onRetryFeature: _controller.retryFeature,
      onOpenLockDisplay: _controller.openLockDisplay,
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
      onCaptureYgdkPhoto:
          hasYgdkSubmissionCapabilities && photoPicker.canCapturePhoto
          ? photoPicker.capturePhoto
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
      onLogout: () => _logoutLocalOwner(localOwner),
      onLogoutAndClearAccount: () => _logoutAndClearLocalData(localOwner),
      onRoutePolicyChanged: (value) {
        unawaited(_controller.setRoutePolicy(value));
      },
      onTelemetryChanged: (value) {
        unawaited(_controller.setTelemetryEnabled(value));
      },
    );
  }
}

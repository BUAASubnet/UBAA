part of 'shell.dart';

extension UbaaShellFeaturePages on _UbaaMainShellState {
  Widget _buildFeaturePage(FeatureId feature) => FeatureReadNavigator(
    key: _readPageKeys.putIfAbsent(
      feature,
      () => GlobalKey<FeatureReadNavigatorState>(),
    ),
    initialHomeTarget: _pendingHomeTarget?.feature == feature
        ? _pendingHomeTarget
        : null,
    onVisibleSnapshot: (snapshot, title) {
      if (_openedFeature == feature &&
          _visiblePage.value != (snapshot, title)) {
        _visiblePage.value = (snapshot, title);
      }
    },
    snapshot: widget.snapshots[feature]!,
    cacheEpoch: widget.readCacheEpoch,
    businessCacheEpoch: _contentEpoch,
    onExit: () => _changeNavigation(() => _openedFeature = null),
    onDepthChanged: (depth) {
      _readDepths[feature] = depth;
      _depthRevision.value++;
    },
    onRetry: () => widget.onRetryFeature(feature),
    onQuery: widget.onFeatureQuery == null
        ? null
        : (query) =>
              feature == FeatureId.cgyy &&
                  query.view == FeatureQueryView.cgyyLockCode
              ? Future<void>.value()
              : widget.onFeatureQuery!(feature, query),
    pageBuilder: (page) => PullToRefresh(
      onRefresh: () => _pull(() => _refreshFeature(feature)),
      enabled:
          _openedFeature == feature &&
          page.isCurrent &&
          widget.writeState.intent == null &&
          !(feature == FeatureId.cgyy &&
              page.query?.view == FeatureQueryView.cgyyLockCode),
      child: FeatureDetailView(
        key: page.pageKey,
        filesAccess: widget.spocFilesAccess,
        isLanding: page.isLanding,
        onOpenLockDisplay: widget.onOpenLockDisplay,
        onReadLockDisplay: widget.onReadLockDisplay,
        lockRefreshRevision: _lockRefreshRevision,
        visible: _openedFeature == feature && page.isCurrent,
        onLoadAllGrades: widget.onLoadAllGrades,
        isBykcChosenDetail: page.isBykcChosenDetail,
        bykcListCourse: page.bykcListCourse,
        bykcPendingCourseId: _bykcWriteActive?.$2,
        writeBusy: _directWriteActive != null,
        onOpenBykcChosen: page.onOpenBykcChosen,
        bykcFilters: _bykcFilters,
        bykcAgenda: _bykcAgendaContext,
        bykcFilterError: _bykcFilterError,
        onBykcFiltersChanged: (value) => unawaited(_saveBykcFilters(value)),
        ygdkRecordsReadback: widget.ygdkRecordsReadback,
        reminderSettings: _effectiveReminder,
        reminderError: _reminderError,
        onReminderChanged: widget.onSaveYgdkReminder == null
            ? null
            : _setReminderEnabled,
        feature: feature,
        snapshot: page.snapshot,
        paginationGeneration: page.paginationGeneration,
        loadingMore: page.loadingMore,
        moreError: page.moreError,
        hasMore: page.hasMore,
        onLoadMore: page.onLoadMore,
        query: page.query,
        backLabel: page.backLabel,
        onBack: page.onBack,
        onRetry: page.onRetry,
        onQuery: page.onQuery,
        onNavigate: page.onNavigate,
        onSwitchView: page.onSwitchView,
        onLoadAcademicTerms: widget.onLoadAcademicTerms,
        onLoadExamTerms: widget.onLoadExamTerms,
        onLoadAcademicWeeks: widget.onLoadAcademicWeeks,
        scheduleImports: widget.scheduleImports,
        onSaveScheduleSemester: widget.onSaveScheduleSemester,
        onCancelScheduleImport: widget.onCancelScheduleImport,
        onLoadCgyyPurposes: widget.onLoadCgyyPurposes,
        onLoadCgyyDefaults: widget.onLoadCgyyDefaults,
        cgyyOnlyAvailable: _cgyyOnlyAvailable,
        onCgyyShowAll: () =>
            _changeNavigation(() => _cgyyOnlyAvailable = false),
        onSaveCgyyDefaults: widget.onSaveCgyyDefaults,
        onScheduleTitle: page.onScheduleTitle,
        readCacheEpoch: _contentEpoch,
        onBykcWrite: !_hasWriteCommands || widget.onPrepareBykcWrite == null
            ? null
            : _startBykcWrite,
        onBykcSignWrite:
            !_hasWriteCommands || widget.onPrepareBykcSignWrite == null
            ? null
            : _startBykcSignWrite,
        onFetchSigninQr: widget.onFetchSigninQr,
        onSaveSigninQr: widget.onSaveSigninQr,
        onCheckSigninStatus: widget.onCheckSigninStatus,
        onSigninWrite: !_hasWriteCommands || widget.onPrepareSigninWrite == null
            ? null
            : _startSigninWrite,
        onCgyyCancelWrite:
            !_hasWriteCommands || widget.onPrepareCgyyCancelWrite == null
            ? null
            : _startCgyyCancelWrite,
        onLibbookReserveWrite:
            !_hasWriteCommands || widget.onPrepareLibbookReserveWrite == null
            ? null
            : _startLibbookReserveWrite,
        onLibbookCancelWrite:
            !_hasWriteCommands || widget.onPrepareLibbookCancelWrite == null
            ? null
            : _startLibbookCancelWrite,
        onEvaluationWrite:
            !_hasWriteCommands || widget.onPrepareEvaluationWrite == null
            ? null
            : _startEvaluation,
        onCgyySubmitWrite:
            !_hasWriteCommands || widget.onPrepareCgyySubmitWrite == null
            ? null
            : _startCgyySubmitWrite,
        onYgdkSubmitWrite: !_hasYgdkSubmissionCapabilities
            ? null
            : _startYgdkSubmitWrite,
        onSpocSubmitWrite:
            !_hasWriteCommands || widget.onPrepareSpocSubmitWrite == null
            ? null
            : _startSpocSubmitWrite,
        onPickSpocSubmitFile: widget.onPickSpocSubmitFile,
        onCaptureYgdkPhoto: _hasYgdkSubmissionCapabilities
            ? widget.onCaptureYgdkPhoto
            : null,
        onPickYgdkPhoto: _hasYgdkSubmissionCapabilities
            ? widget.onPickYgdkPhoto
            : null,
      ),
    ),
  );
}

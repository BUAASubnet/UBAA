part of 'shell.dart';

extension UbaaShellNavigation on _UbaaMainShellState {
  void _goBack() {
    if (_utilityPage == '云盘' && _bhpanBack.handleBack()) return;
    if (_utilityPage != null) {
      _changeNavigation(() => _utilityPage = null);
    } else {
      _readPageKeys[_openedFeature]?.currentState?.goBack();
    }
  }

  void _selectTab(int index, {bool fromSwipe = false}) {
    if (widget.writeState.intent != null) {
      // 写入进行中不能换页；滑动已移动的页面退回原位。
      if (fromSwipe && _tabPager.hasClients) {
        _tabPager.jumpToPage(_selectedIndex);
      }
      return;
    }
    _changeNavigation(() {
      _selectedIndex = index;
      _utilityPage = null;
      _openedFeature = null;
    });
    if (!fromSwipe &&
        index < UiDestination.settings.index &&
        _tabPager.hasClients) {
      _tabPager.jumpToPage(index);
    }
    if (index == UiDestination.me.index) _ensureCampusAccountLoaded();
  }

  void _openUtility(String page) {
    if (widget.writeState.intent != null) return;
    if (page == UiDestination.settings.label &&
        MediaQuery.sizeOf(context).width >= 600) {
      _selectTab(UiDestination.settings.index);
      return;
    }
    _changeNavigation(
      () {
        _openedFeature = null;
        _utilityPage = page;
      },
      openedFeature: switch (page) {
        '图书馆云打印' => 'cloud_print',
        '云盘' => 'bhpan',
        'iHome' => 'ihome',
        '财务查询' => 'finance',
        '当前借阅' => 'library_loans',
        healthCloudTitle => 'health_cloud',
        _ => null,
      },
    );
  }

  void _openHomeNavigation(FeatureReadNavigation target) {
    final page = _readPageKeys[target.feature]?.currentState;
    _changeNavigation(() {
      _openedFeature = target.feature;
      if (page == null) _pendingHomeTarget = target;
    }, openedFeature: target.feature.wireName);
    _recordFeatureVisit(target.feature);
    if (page != null) {
      unawaited(page.openFromHome(target));
    } else {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _pendingHomeTarget = null,
      );
    }
  }

  void _openHomeTodo(HomeTodo item) {
    final target = item.navigation;
    if (target != null) {
      _openHomeNavigation(target);
    } else if (item.feature == FeatureId.schedule) {
      _selectTab(UiDestination.agenda.index);
    }
  }

  Widget _buildTab(BuildContext context) => _utilityPage != null
      ? _utilityPage == '图书馆云打印'
            ? CloudPrintView(
                key: ValueKey(_pageContentScope),
                service: widget.cloudPrintService,
                connecting: widget.connecting,
                pickFiles: widget.onPickPrintFiles,
                pickFolder: widget.onPickPrintFolder,
                previewPdf: widget.onPreviewScanPdf,
                renderPdf: widget.onRenderScanPdf,
              )
            : _utilityPage == '云盘'
            ? BhpanView(
                key: ValueKey(_pageContentScope),
                scopeKey: _pageContentScope,
                connecting: widget.connecting,
                backHandle: _bhpanBack,
                access: BhpanAccess(
                  service: widget.bhpanService,
                  pickFile: widget.onPickBhpanFile,
                  pickDownload: widget.onPickBhpanDownload,
                  previewFile: widget.onPreviewBhpanFile,
                  recordDeliveryFailure: widget.onBhpanDeliveryFailure,
                  runWrite: _hasWriteCommands ? _runBhpanWrite : null,
                ),
              )
            : _utilityPage == 'iHome'
            ? IhomeView(
                key: ValueKey(_pageContentScope),
                scopeKey: _pageContentScope,
                connecting: widget.connecting,
                service: widget.ihomeService,
              )
            : _utilityPage == healthCloudTitle
            ? HealthCloudView(read: widget.healthCloudRead)
            : _utilityPage == '财务查询'
            ? FinanceView(
                key: ValueKey(_pageContentScope),
                scopeKey: _pageContentScope,
                connecting: widget.connecting,
                service: widget.financeService,
              )
            : _utilityPage == '当前借阅' && widget.readLibraryLoans != null
            ? LibraryLoansView(
                key: ValueKey(_pageContentScope),
                read: widget.readLibraryLoans!,
                pending: widget.pendingLibraryLoans,
                recheck: widget.onRecheckLibraryLoan,
                renew:
                    widget.onPrepareLibraryLoanRenewWrite == null ||
                        !_hasWriteCommands
                    ? null
                    : _startLibraryLoanRenewWrite,
              )
            : _utilityPage == '关于'
            ? AboutView(
                loadVersion: widget.onLoadAppVersion,
                openLink: widget.onOpenAppLink,
              )
            : _buildProfile()
      : _selectedIndex == UiDestination.settings.index
      ? _buildProfile()
      : MediaQuery.sizeOf(context).width >= 600
      ? _buildTabPage(context, _selectedIndex)
      : _buildTabPager(context);
  Widget _buildTabPager(BuildContext context) {
    _tabPager = currentTabPager(_tabPager, _selectedIndex);
    return TabPager(
      controller: _tabPager,
      selectedIndex: _selectedIndex,
      enabled: widget.writeState.intent == null,
      itemCount: UiDestination.settings.index,
      onSelected: (index) => _selectTab(index, fromSwipe: true),
      itemBuilder: _buildTabPage,
    );
  }

  Widget _buildTabPage(BuildContext context, int index) => switch (index) {
    0 => HomeView(
      onVisibilityChanged: widget.onHomeVisibilityChanged,
      key: _homeKey,
      onPullRefresh: _pull,
      homeClock: widget.homeClock,
      recentFeatures: _recentFeatures,
      state:
          widget.homeState ??
          HomeState(
            now: (widget.homeClock ?? clock).now(),
            sources: widget.snapshots,
            projected: true,
            schedule: HomeScheduleState(
              date: homeDateKey(
                homeCampusTime((widget.homeClock ?? clock).now()),
              ),
              snapshot: widget.snapshots[FeatureId.schedule]!,
            ),
          ),
      visible:
          _openedFeature == null &&
          _utilityPage == null &&
          _selectedIndex == 0 &&
          widget.writeState.intent == null,
      onTodoTap: _openHomeTodo,
      onViewAllTodos: () {
        _changeNavigation(() => _agendaTodoRequest++);
        _selectTab(UiDestination.agenda.index);
      },
      writeReadbackNotice:
          widget.writeReadbacks.isEmpty && widget.writeReadbackError == null
          ? null
          : WriteReadbackNotice(
              key: ValueKey(
                '${widget.cacheAccountId}:${widget.readCacheEpoch}',
              ),
              hints: widget.writeReadbacks,
              error: widget.writeReadbackError,
              onDismiss: widget.onDismissWriteReadback,
              onRefresh: widget.onRefreshWriteReadbacks,
              onOpenFeature: (feature) {
                _changeNavigation(
                  () => _openedFeature = feature,
                  openedFeature: feature.wireName,
                );
                _recordFeatureVisit(feature);
              },
            ),
      appNotices: widget.appNotices,
      gradeScoreNotice: widget.gradeScoreNotice,
      gradeCheckRoute: widget.gradeCheckRoute,
      onOpenGradeNotice: _openGradeNotice,
      onDismissGradeNotice: widget.onConsumeGradeNotice,
      onSignin: _hasWriteCommands && widget.onPrepareSigninWrite != null
          ? _performHomeSignin
          : null,
      onObserveProgress: _observeHomeProgress,
      onFeatureTap: _openFeatureList,
      onRetryFeature: widget.onRetryHomeSource ?? widget.onRetryFeature,
      onRefresh: () =>
          _joinRefresh('home', widget.onRefreshHome ?? widget.onRefresh),
    ),
    2 => AgendaView(
      signedIn: widget.user != null || widget.cacheAccountId != null,
      service: widget.agenda.service,
      prepareSync: widget.agenda.prepareSync,
      syncScopeKey: widget.routePolicy,
      failure: widget.agenda.failure,
      scopeKey: (widget.cacheAccountId, widget.routePolicy),
      projectionKey: (
        widget.readCacheEpoch,
        widget.businessCacheEpoch,
        widget.agendaEpoch,
      ),
      route: agendaRoute(
        widget.routePolicy,
        widget.activeRoutes,
        schoolRoute: widget.agendaSchoolRoute,
      ),
      term: widget.agenda.term,
      todoRequest: _agendaTodoRequest,
      visible:
          _selectedIndex == UiDestination.agenda.index &&
          _openedFeature == null,
      now: widget.homeClock == null
          ? null
          : campusDate(widget.homeClock!.now()),
      reminder:
          _effectiveReminder ?? const YgdkReminderSettings(enabled: false),
      onOpenSchool: _openHomeNavigation,
      onRefreshSchool: () => _joinRefresh('home-core', widget.onRefresh),
      onImportSchedule: _importAgendaSchedule,
      onEnsureSchedule: widget.connecting ? null : widget.agenda.ensureSchedule,
      onChanged: widget.agenda.onChanged,
      onSaveFile: widget.agenda.saveFile,
    ),
    1 || 3 => FeatureGridView(
      onOpenCloudPrint:
          index == UiDestination.campus.index &&
              widget.cloudPrintService != null
          ? () => _openUtility('图书馆云打印')
          : null,
      onOpenBhpan: index == UiDestination.campus.index
          ? () => _openUtility('云盘')
          : null,
      onOpenIhome: index == UiDestination.campus.index
          ? () => _openUtility('iHome')
          : null,
      onOpenHealthCloud:
          index == UiDestination.campus.index && widget.healthCloudRead != null
          ? () => _openUtility(healthCloudTitle)
          : null,
      onOpenFinance:
          index == UiDestination.campus.index && widget.financeService != null
          ? () => _openUtility('财务查询')
          : null,
      features: _UbaaMainShellState._tabs[index].features,
      homeState: widget.homeState,
      snapshots: widget.snapshots,
      onFeatureTap: _openFeatureList,
      onRetryFeature: widget.onRetryFeature,
    ),
    4 => PullToRefresh(
      onRefresh: () => _pull(_refreshCampusAccount),
      enabled:
          widget.campusAccountService != null &&
          widget.writeState.intent == null,
      child: MeView(
        onOpenBhpan: () => _openUtility('云盘'),
        onOpenLibraryLoans: widget.readLibraryLoans == null
            ? null
            : () => _openUtility('当前借阅'),
        user: widget.user,
        overview: _campusOverview,
        showShortcuts: MediaQuery.sizeOf(context).width < 600,
        onOpenProfile: () => _openUtility('我的资料'),
        onOpenSettings: () => _openUtility(UiDestination.settings.label),
        onOpenAbout: () => _openUtility('关于'),
        onLogout: _logout,
      ),
    ),
    _ => _buildProfile(),
  };
  Widget _buildProfile() => ProfileView(
    cacheAccountId: widget.cacheAccountId,
    canClearBusinessCache: widget.canClearBusinessCache,
    onReadCacheUsage: widget.onReadCacheUsage,
    onClearBusinessCache: widget.onClearBusinessCache,
    settingsOnly:
        _utilityPage == '设置' ||
        (_utilityPage == null &&
            _selectedIndex == UiDestination.settings.index),
    onOpenProfile: () => _selectTab(UiDestination.me.index),
    onOpenAbout: () => _openUtility('关于'),
    user: widget.user,
    routePolicy: widget.routePolicy,
    appService: widget.appService,
    onRoutePolicyChanged: widget.onRoutePolicyChanged,
    onLogout: _logout,
    onLogoutAndClearAccount: widget.onLogoutAndClearAccount,
    activeRoutes: widget.activeRoutes,
    onReadDiagnostics: widget.onReadDiagnostics,
    appearance: widget.appearance,
  );
  Widget _buildRailContent(BuildContext context) => uiShellRail(
    context,
    selectedIndex: _selectedIndex,
    utilityPage: _utilityPage,
    featureOpen: _openedFeature != null,
    leading: (extended) => _buildRailLeading(context, extended),
    onSelectTab: _selectTab,
    onOpenAbout: () => _openUtility('关于'),
  );

  Widget _buildRailLeading(
    BuildContext context,
    bool extended, {
    VoidCallback? onTap,
  }) => uiRailIdentity(
    context,
    extended,
    user: widget.user,
    // “我的资料”是“我的”的下一级，打开时身份区保持高亮。
    selected:
        _selectedIndex == UiDestination.me.index &&
        (_utilityPage == null || _utilityPage == '我的资料'),
    onTap: onTap ?? () => _selectTab(UiDestination.me.index),
  );

  Future<void> _logout() async {
    if (widget.writeState.intent != null) return;
    await widget.onLogout();
  }

  Future<void> _joinRefresh(Object key, Future<void> Function() action) =>
      joinUiRefresh(_refreshes, key, action);

  /// 标题栏按钮与快捷键走首页自身的刷新，补充来源一起重读。
  Future<void> _refreshHome() =>
      _joinRefresh('home', widget.onRefreshHome ?? widget.onRefresh);

  Future<void> _importAgendaSchedule() => importAgendaSchedule(
    context,
    widget.agenda.term,
    widget.onSaveScheduleSemester,
    () => _openFeatureList(FeatureId.schedule),
    (save) => _joinRefresh('agenda-semester', save),
  );

  Future<void> _refreshFeature(FeatureId feature) =>
      _joinRefresh(feature, () async {
        final page = _readPageKeys[feature]?.currentState;
        if (feature == FeatureId.cgyy &&
            page?.currentFrame.query?.view == FeatureQueryView.cgyyLockCode) {
          _refreshLockDisplay();
        } else if (feature == FeatureId.schedule &&
            widget.onSaveScheduleSemester != null &&
            (page?.currentFrame.query?.term?.trim().isNotEmpty ?? false)) {
          await widget.onSaveScheduleSemester!(page!.currentFrame.query!.term!);
        } else {
          await page?.refreshCurrent();
        }
      });
}

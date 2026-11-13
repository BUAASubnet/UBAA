part of 'shell.dart';

/// 自适应导航的展示；页面与写入状态由 Shell 持有。
extension UbaaShellNavigation on _UbaaMainShellState {
  Widget _withRefreshShortcuts(
    Widget shell,
    Future<void> Function()? refreshPage,
  ) {
    // 桌面快捷键的父层级保持稳定，切页时只调整可用的绑定。
    void refresh() => unawaited(refreshPage?.call());
    return CallbackShortcuts(
      bindings: {
        if (refreshPage != null)
          const SingleActivator(LogicalKeyboardKey.keyR, meta: true): refresh,
        if (refreshPage != null)
          const SingleActivator(LogicalKeyboardKey.keyR, control: true):
              refresh,
      },
      child: Focus(autofocus: true, child: shell),
    );
  }

  void _goBack() {
    if (_utilityPage == '北航云盘' && _bhpanBack.handleBack()) return;
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
    _changeNavigation(() {
      _openedFeature = null;
      _utilityPage = page;
    });
  }

  void _openHomeNavigation(FeatureReadNavigation target) {
    final page = _readPageKeys[target.feature]?.currentState;
    _changeNavigation(() {
      _openedFeature = target.feature;
      if (page == null) _pendingHomeTarget = target;
    });
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
    if (target == null) return;
    _openHomeNavigation(target);
  }

  /// 手机上首页、三个分类与“我的”可左右滑动切换；各页保留状态。
  Widget _buildTab(BuildContext context) => _utilityPage != null
      ? _utilityPage == '北航云盘'
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
            : _utilityPage == '财务查询'
            ? FinanceView(
                key: ValueKey(_pageContentScope),
                scopeKey: _pageContentScope,
                connecting: widget.connecting,
                service: widget.financeService,
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
    themeMode: widget.themeMode,
    onThemeModeChanged: widget.onThemeModeChanged,
  );

  Widget _buildRail(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(
      // 导航只在内容溢出时滚动，边界不随触摸板回弹。
      physics: const ClampingScrollPhysics(),
    ),
    child: _buildRailContent(context),
  );

  Widget _buildRailContent(BuildContext context) {
    final extended = MediaQuery.sizeOf(context).width >= 1000;
    final colors = Theme.of(context).colorScheme;
    if (!extended) {
      final railButtonStyle =
          IconButton.styleFrom(minimumSize: const Size(56, 48)).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? colors.secondaryContainer
                  : null,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? colors.onSecondaryContainer
                  : null,
            ),
          );
      // 矮窗口收紧间距、设置紧跟分组、省去“关于”（在“我的”页），不再遮住分组。
      return LayoutBuilder(
        builder: (context, constraints) {
          final short = constraints.maxHeight < 560;
          return NavigationRail(
            scrollable: true,
            minWidth: 88,
            selectedIndex: _selectedIndex < 4 && _utilityPage == null
                ? _selectedIndex
                : null,
            onDestinationSelected: _selectTab,
            labelType: NavigationRailLabelType.none,
            leading: _buildRailLeading(context, false),
            trailingAtBottom: !short,
            trailing: Padding(
              padding: EdgeInsets.only(bottom: short ? 8 : 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '设置',
                    isSelected:
                        _selectedIndex == UiDestination.settings.index &&
                        _utilityPage == null,
                    style: railButtonStyle,
                    onPressed: () => _selectTab(UiDestination.settings.index),
                    icon: Icon(UiDestination.settings.icon),
                    selectedIcon: Icon(UiDestination.settings.selectedIcon),
                  ),
                  if (!short) ...[
                    const SizedBox(height: 8),
                    IconButton(
                      tooltip: '关于',
                      isSelected:
                          _utilityPage == '关于' && _openedFeature == null,
                      style: railButtonStyle,
                      onPressed: () => _openUtility('关于'),
                      icon: const Icon(Icons.info_outline),
                    ),
                  ],
                ],
              ),
            ),
            destinations: _UbaaMainShellState._tabs
                .take(4)
                .map(
                  (tab) => NavigationRailDestination(
                    padding: EdgeInsets.symmetric(vertical: short ? 0 : 8),
                    icon: Tooltip(
                      message: tab.label,
                      excludeFromSemantics: true,
                      child: Icon(tab.icon),
                    ),
                    selectedIcon: Tooltip(
                      message: tab.label,
                      excludeFromSemantics: true,
                      child: Icon(tab.selectedIcon),
                    ),
                    label: Text(tab.label),
                  ),
                )
                .toList(),
          );
        },
      );
    }
    Widget entry(UiDestination tab) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        selected: _selectedIndex == tab.index && _utilityPage == null,
        selectedTileColor: colors.secondaryContainer,
        selectedColor: colors.onSecondaryContainer,
        leading: Icon(
          _selectedIndex == tab.index ? tab.selectedIcon : tab.icon,
        ),
        title: Text(tab.label),
        onTap: () => _selectTab(tab.index),
      ),
    );
    return Material(
      color: colors.surfaceContainer,
      child: SizedBox(
        width: 248,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                child: _buildRailLeading(context, true),
              ),
              Expanded(
                child: ListView(
                  primary: false,
                  children: [
                    for (final tab in _UbaaMainShellState._tabs.take(4))
                      entry(tab),
                  ],
                ),
              ),
              entry(UiDestination.settings),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 3, 12, 16),
                child: ListTile(
                  selected: _utilityPage == '关于' && _openedFeature == null,
                  selectedTileColor: colors.secondaryContainer,
                  selectedColor: colors.onSecondaryContainer,
                  leading: Icon(
                    _utilityPage == '关于' ? Icons.info : Icons.info_outline,
                  ),
                  title: const Text('关于'),
                  onTap: () => _openUtility('关于'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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

  /// 写操作进行中不退出；侧栏不再放退出入口，统一在设置页的「账号」分组。
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
                _changeNavigation(() => _openedFeature = feature);
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
      reminder: _reminderSettings,
      onOpenSchool: _openHomeNavigation,
      onRefreshSchool: () => _joinRefresh('home-core', widget.onRefresh),
      onImportSchedule: _importAgendaSchedule,
      onEnsureSchedule: widget.connecting ? null : widget.agenda.ensureSchedule,
      onChanged: widget.agenda.onChanged,
      onSaveFile: widget.agenda.saveFile,
    ),
    1 || 3 => FeatureGridView(
      onOpenBhpan: index == UiDestination.campus.index
          ? () => _openUtility('北航云盘')
          : null,
      onOpenIhome: index == UiDestination.campus.index
          ? () => _openUtility('iHome')
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
        onOpenBhpan: () => _openUtility('北航云盘'),
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
}

part of '../widgets.dart';

/// 主界面容器：窄屏使用底部导航，桌面宽屏使用侧边导航。
class UbaaMainShell extends StatefulWidget {
  const UbaaMainShell({
    required this.user,
    required this.snapshots,
    required this.routePolicy,
    required this.telemetryEnabled,
    required this.onRefresh,
    required this.onRetryFeature,
    required this.onLogout,
    required this.onLogoutAndClearAccount,
    required this.onRoutePolicyChanged,
    required this.onTelemetryChanged,
    this.initialTab = 0,
    this.connectionStatus,
    this.onReconnect,
    this.onCompleteLogin,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.readCacheEpoch = 0,
    this.businessCacheEpoch = 0,
    this.cacheAccountId,
    this.canClearBusinessCache = true,
    this.onReadCacheUsage,
    this.onClearBusinessCache,
    this.onLoadAcademicTerms,
    this.onLoadAcademicWeeks,
    this.scheduleImports = const {},
    this.onSaveScheduleSemester,
    this.onCancelScheduleImport,
    this.onLoadCgyyPurposes,
    this.onLoadAppVersion,
    this.onOpenAppLink,
    this.onLoadAllGrades,
    this.gradeScoreNotice,
    this.gradeCheckRoute,
    this.onCheckGradeUpdates,
    this.onConsumeGradeNotice,
    this.ygdkRecordsReadback,
    this.homeSnapshots,
    this.onLoadHomeSupplement,
    this.onLoadYgdkReminder,
    this.onSaveYgdkReminder,
    this.activeRoutes = const <ConnectionMode>[],
    this.onReadDiagnostics,
    this.writeState = const WriteState.idle(),
    this.onRunWritePrepare,
    this.onCancelWrite,
    this.onConfirmWrite,
    this.onFeatureQuery,
    this.onPrepareBykcWrite,
    this.onPrepareBykcSignWrite,
    this.onPrepareSigninWrite,
    this.onPrepareCgyyCancelWrite,
    this.onPrepareLibbookReserveWrite,
    this.onPrepareLibbookCancelWrite,
    this.onPrepareCgyySubmitWrite,
    this.onPrepareEvaluationWrite,
    this.onPrepareYgdkSubmitWrite,
    this.onPickYgdkPhoto,
    this.onCaptureYgdkPhoto,
    this.onDiscardWriteIntent,
    this.onCommitWrite,
    this.onWriteSuccess,
    this.onVerifyCgyyReceipt,
    this.onVerifyCgyyCancellation,
    this.onRefreshEvaluationAfterWrite,
    this.onRefreshYgdkAfterWrite,
    super.key,
  });

  final UserSummary? user;
  final Map<FeatureId, FeatureSnapshot> snapshots;

  /// 仅用于呈现原协调器已完成的固定路线记录回读，不触发新读取。
  final FeatureSnapshot? ygdkRecordsReadback;
  final Map<FeatureId, FeatureSnapshot>? homeSnapshots;
  final Future<FeatureResult> Function(HomeSupplement source, bool force)?
  onLoadHomeSupplement;
  final Future<YgdkReminderSettings> Function()? onLoadYgdkReminder;
  final Future<void> Function(YgdkReminderSettings)? onSaveYgdkReminder;
  final RoutePolicy routePolicy;
  final bool telemetryEnabled;
  final Future<void> Function() onRefresh;
  final Future<void> Function(FeatureId feature) onRetryFeature;
  final Future<void> Function() onLogout;
  final Future<void> Function() onLogoutAndClearAccount;
  final ValueChanged<RoutePolicy> onRoutePolicyChanged;
  final ValueChanged<bool> onTelemetryChanged;

  /// 供宿主恢复上次导航位置或集成测试从指定功能分组启动。
  final int initialTab;
  final String? connectionStatus;
  final VoidCallback? onReconnect;
  final ValueChanged<BuildContext>? onCompleteLogin;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  /// 应用读取生命周期改变时使父返回缓存失效，当前页面草稿仍由页面持有。
  final int readCacheEpoch;
  final int businessCacheEpoch;
  final String? cacheAccountId;
  final bool canClearBusinessCache;
  final Future<CacheUsageSummary> Function(String)? onReadCacheUsage;
  final Future<CacheClearOutcome> Function(String)? onClearBusinessCache;

  /// 用户打开学期选择器后读取独立选项，不改写课表结果页。
  final Future<FeatureResult> Function(bool forceRefresh)? onLoadAcademicTerms;
  final Future<FeatureResult> Function(String term, bool forceRefresh)?
  onLoadAcademicWeeks;
  final Map<String, ScheduleImportState> scheduleImports;
  final Future<void> Function(String)? onSaveScheduleSemester;
  final ValueChanged<String>? onCancelScheduleImport;
  final Future<FeatureResult> Function(bool forceRefresh)? onLoadCgyyPurposes;
  final Future<String?> Function()? onLoadAppVersion;
  final Future<bool> Function(AppLink)? onOpenAppLink;
  final GradesAggregateLoader? onLoadAllGrades;
  final GradeScoreNotice? gradeScoreNotice;
  final ConnectionMode? gradeCheckRoute;
  final Future<void> Function()? onCheckGradeUpdates;
  final VoidCallback? onConsumeGradeNotice;
  final List<ConnectionMode> activeRoutes;

  /// 宿主提供本轮允许字段的脱敏报告，不读取账号或业务数据。
  final String Function()? onReadDiagnostics;
  final WriteState writeState;
  final WritePreparationRunner? onRunWritePrepare;
  final WriteCancellationRunner? onCancelWrite;
  final WriteConfirmationRunner? onConfirmWrite;
  final Future<void> Function(FeatureId feature, FeatureQuery query)?
  onFeatureQuery;
  final Future<WriteIntent> Function(WriteOperation operation, int courseId)?
  onPrepareBykcWrite;
  final BykcSignPreparer? onPrepareBykcSignWrite;
  final SigninPreparer? onPrepareSigninWrite;
  final CgyyCancelPreparer? onPrepareCgyyCancelWrite;
  final LibbookReservePreparer? onPrepareLibbookReserveWrite;
  final LibbookCancelPreparer? onPrepareLibbookCancelWrite;
  final CgyyReservationPreparer? onPrepareCgyySubmitWrite;
  final EvaluationSubmitPreparer? onPrepareEvaluationWrite;
  final YgdkSubmitPreparer? onPrepareYgdkSubmitWrite;
  final YgdkPhotoPicker? onPickYgdkPhoto;
  final YgdkPhotoPicker? onCaptureYgdkPhoto;
  final WriteIntentDiscarder? onDiscardWriteIntent;
  final Future<WriteCommitResult> Function(String intentId)? onCommitWrite;
  final WriteSuccessHandler? onWriteSuccess;

  /// 在 [onWriteSuccess] 刷新研讨室订单后，用提交收据匹配只读订单编号。
  final CgyyReceiptVerifier? onVerifyCgyyReceipt;
  final CgyyCancellationVerifier? onVerifyCgyyCancellation;
  // 按已确认意图的路线执行一次评教只读回读。
  final EvaluationSubmissionRefresher? onRefreshEvaluationAfterWrite;
  final YgdkSubmissionRefresher? onRefreshYgdkAfterWrite;

  @override
  State<UbaaMainShell> createState() => _UbaaMainShellState();
}

class _UbaaMainShellState extends State<UbaaMainShell> {
  Map<String, ConnectionMode> _homeReadRoutes = {};
  Map<String, ConnectionMode> _gradesReadRoutes = {};
  YgdkReminderSettings? _reminderSettings;
  String? _reminderError;
  int _reminderRevision = 0;
  late int _selectedIndex;
  FeatureId? _openedFeature;
  String? _utilityPage;
  final _visiblePage = ValueNotifier<(FeatureSnapshot, String)?>(null);
  final Set<FeatureId> _visitedFeatures = <FeatureId>{};
  int _accountGeneration = 0;
  final Map<FeatureId, GlobalKey<_FeatureReadNavigatorState>> _readPageKeys =
      {};

  bool get _hasWriteCommands =>
      widget.onRunWritePrepare != null &&
      widget.onCancelWrite != null &&
      widget.onConfirmWrite != null;

  bool get _hasYgdkSubmissionCapabilities =>
      _hasWriteCommands &&
      widget.onPrepareYgdkSubmitWrite != null &&
      widget.onPickYgdkPhoto != null &&
      widget.onRefreshYgdkAfterWrite != null &&
      widget.onCommitWrite != null &&
      widget.onDiscardWriteIntent != null;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab.clamp(0, _tabs.length - 1);
    unawaited(_loadReminderSettings());
  }

  @override
  void didUpdateWidget(covariant UbaaMainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.user?.accountScope ?? oldWidget.user?.username) !=
        (widget.user?.accountScope ?? widget.user?.username)) {
      _accountGeneration++;
      _homeReadRoutes = {};
      _gradesReadRoutes = {};
      _reminderSettings = null;
      _reminderError = null;
      _reminderRevision++;
      unawaited(_loadReminderSettings());
      _visitedFeatures.clear();
      _readPageKeys.clear();
      _openedFeature = null;
      _utilityPage = null;
      _visiblePage.value = null;
    }
  }

  Future<void> _loadReminderSettings() async {
    final generation = _accountGeneration;
    final load = widget.onLoadYgdkReminder;
    if (load == null) {
      _reminderSettings = const YgdkReminderSettings();
      return;
    }
    try {
      final value = await load();
      if (mounted && generation == _accountGeneration)
        setState(() => _reminderSettings = value);
    } on Object {
      if (mounted && generation == _accountGeneration)
        setState(() => _reminderError = '提醒设置读取失败');
    }
  }

  Future<void> _saveReminderSettings(YgdkReminderSettings value) async {
    final save = widget.onSaveYgdkReminder;
    if (save == null) return;
    final before = _reminderSettings, generation = _accountGeneration;
    final revision = ++_reminderRevision;
    setState(() {
      _reminderSettings = value;
      _reminderError = null;
    });
    try {
      await save(value);
    } on Object {
      if (mounted &&
          generation == _accountGeneration &&
          revision == _reminderRevision) {
        setState(() {
          _reminderSettings = before;
          _reminderError = '提醒设置保存失败，请重试';
        });
      }
    }
  }

  void _setReminderEnabled(bool enabled) {
    final current = _reminderSettings;
    if (current != null)
      unawaited(_saveReminderSettings(current.copyWith(enabled: enabled)));
  }

  void _observeHomeProgress(WeekPresentation week, YgdkOverview overview) {
    final current = _reminderSettings;
    if (current == null ||
        !current.enabled ||
        !week.current ||
        week.responseTerm.trim().isEmpty)
      return;
    final weekKey = '${week.responseTerm}:${week.number}';
    final weekDone =
        (overview.weekCount ?? -1) >= 4 && current.weekDoneKey != weekKey;
    final termDone =
        overview.termCount >= 16 && current.termDoneKey != week.responseTerm;
    if (!weekDone && !termDone) return;
    unawaited(
      _saveReminderSettings(
        current.copyWith(
          weekDoneKey: weekDone ? weekKey : null,
          termDoneKey: termDone ? week.responseTerm : null,
        ),
      ),
    );
  }

  void _openHomeTodo(HomeTodo item) {
    final target = item.navigation;
    if (target == null) return;
    _openHomeNavigation(target);
  }

  void _openGradeNotice() {
    final notice = widget.gradeScoreNotice;
    if (notice == null) return;
    widget.onConsumeGradeNotice?.call();
    _openHomeNavigation(
      FeatureReadNavigation(
        feature: FeatureId.grades,
        query: FeatureQuery(term: notice.termCode),
      ),
    );
  }

  void _openHomeNavigation(FeatureReadNavigation target) {
    final generation = _accountGeneration;
    setState(() => _openedFeature = target.feature);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          generation == _accountGeneration &&
          _openedFeature == target.feature) {
        unawaited(
          _readPageKeys[target.feature]?.currentState?.openFromHome(target),
        );
      }
    });
  }

  @override
  void dispose() {
    _visiblePage.dispose();
    super.dispose();
  }

  static const _tabs = <({String label, IconData icon, IconData selectedIcon})>[
    (label: '主页', icon: Icons.home_outlined, selectedIcon: Icons.home),
    (label: '普通功能', icon: Icons.apps_outlined, selectedIcon: Icons.apps),
    (
      label: '高级功能',
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final pendingWrite = widget.writeState.intent;
    if (_openedFeature case final feature?) _visitedFeatures.add(feature);
    final pages = _visitedFeatures.toList(growable: false);
    // 只保留已访问页面的 State；每次 build 都读取当前快照和回调。
    final body = IndexedStack(
      key: ValueKey<int>(_accountGeneration),
      index: pendingWrite != null
          ? pages.length + 1
          : _openedFeature == null
          ? 0
          : pages.indexOf(_openedFeature!) + 1,
      children: <Widget>[
        _buildTab(context),
        for (final feature in pages)
          TickerMode(
            key: ValueKey<FeatureId>(feature),
            enabled: pendingWrite == null && _openedFeature == feature,
            child: _buildFeaturePage(feature),
          ),
        if (pendingWrite != null)
          WriteConfirmationView(
            showTitle: false,
            showRoute: false,
            intent: pendingWrite,
            onCancel: _cancelWrite,
            onConfirm: _confirmWrite,
            isSubmitting: widget.writeState.isSubmitting,
            isDiscarding: widget.writeState.isDiscarding,
            error: widget.writeState.error,
          ),
      ],
    );
    return PopScope<void>(
      canPop: pendingWrite == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop &&
            pendingWrite != null &&
            !widget.writeState.isSubmitting) {
          unawaited(_cancelWrite());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          toolbarHeight: 56,
          title: ValueListenableBuilder<(FeatureSnapshot, String)?>(
            valueListenable: _visiblePage,
            builder: (context, page, _) => Text(
              pendingWrite != null
                  ? '确认${pendingWrite.operation.title}'
                  : _openedFeature != null
                  ? (page?.$1.feature == _openedFeature
                        ? page!.$2
                        : _openedFeature!.title)
                  : (_utilityPage ??
                        (_selectedIndex == 0
                            ? '首页'
                            : _tabs[_selectedIndex].label)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          leading: pendingWrite != null
              ? IconButton(
                  tooltip: '取消并返回',
                  onPressed: widget.writeState.isSubmitting
                      ? null
                      : _cancelWrite,
                  icon: const Icon(Icons.arrow_back),
                )
              : _openedFeature != null || _utilityPage != null
              ? IconButton(
                  tooltip: '返回',
                  onPressed: () {
                    if (_utilityPage != null) {
                      setState(() => _utilityPage = null);
                    } else {
                      _readPageKeys[_openedFeature]?.currentState?.goBack();
                    }
                  },
                  icon: const Icon(Icons.arrow_back),
                )
              : null,
          actions: <Widget>[
            ValueListenableBuilder<(FeatureSnapshot, String)?>(
              valueListenable: _visiblePage,
              builder: (context, page, _) {
                final snapshot = page?.$1;
                final homeVisible =
                    _openedFeature == null &&
                    _utilityPage == null &&
                    _selectedIndex == 0 &&
                    pendingWrite == null;
                final pageRoutes = homeVisible
                    ? _homeReadRoutes
                    : _openedFeature == FeatureId.grades && pendingWrite == null
                    ? _gradesReadRoutes
                    : null;
                final homeRoutes =
                    pageRoutes?.values.toSet() ?? <ConnectionMode>{};
                final mixed = homeRoutes.length > 1;
                final route =
                    pendingWrite?.resolvedRoute ??
                    (pageRoutes != null && pageRoutes.isNotEmpty
                        ? (homeRoutes.length == 1 ? homeRoutes.single : null)
                        : (_openedFeature == snapshot?.feature
                              ? snapshot?.resolvedRoute
                              : null));
                return IconButton(
                  tooltip: '实际路线：${mixed ? '混合' : route?.label ?? '未确定'}',
                  icon: Icon(
                    route == ConnectionMode.direct
                        ? Icons.lan_outlined
                        : route == ConnectionMode.webvpn
                        ? Icons.vpn_lock_outlined
                        : Icons.route_outlined,
                  ),
                  onPressed: () =>
                      _showRouteOptions(context, route, homeRoutes: pageRoutes),
                );
              },
            ),
            if (_openedFeature != null && pendingWrite == null)
              IconButton(
                tooltip: '搜索与筛选',
                onPressed: () =>
                    _readPageKeys[_openedFeature]?.currentState?.openPanel(),
                icon: const Icon(Icons.search),
              ),
            if (_openedFeature != null && pendingWrite == null)
              IconButton(
                tooltip: '刷新当前查询',
                onPressed: () => _readPageKeys[_openedFeature]?.currentState
                    ?.refreshCurrent(),
                icon: const Icon(Icons.refresh),
              ),
            if (_openedFeature == null &&
                _utilityPage == null &&
                _selectedIndex == 0 &&
                pendingWrite == null)
              IconButton(
                tooltip: '刷新',
                onPressed: () => widget.onRefresh(),
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        drawer: pendingWrite == null ? _buildDrawer(context) : null,
        // 保持内容父层级与 key 稳定，宽窄切换不销毁已访问页面。
        body: Column(
          children: [
            // 保持占位与内容索引固定，连接提示消失时不销毁页面和草稿。
            if (widget.connectionStatus == null)
              const SizedBox.shrink()
            else
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.connectionStatus!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onCompleteLogin == null
                            ? widget.onReconnect
                            : () => widget.onCompleteLogin!(context),
                        child: Text(
                          widget.onCompleteLogin == null ? '重试' : '完成登录',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Row(
                children: <Widget>[
                  if (wide) _buildRail(context),
                  if (wide) const VerticalDivider(width: 1),
                  Expanded(
                    key: const ValueKey<String>('feature-pages'),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: body,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar:
            wide ||
                _openedFeature != null ||
                _utilityPage != null ||
                pendingWrite != null
            ? null
            : NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _selectTab,
                destinations: _tabs
                    .map(
                      (tab) => NavigationDestination(
                        key: ValueKey<String>('tab-${tab.label}'),
                        icon: Icon(tab.icon),
                        selectedIcon: Icon(tab.selectedIcon),
                        label: tab.label,
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }

  Widget _buildFeaturePage(FeatureId feature) => _FeatureReadNavigator(
    key: _readPageKeys.putIfAbsent(
      feature,
      () => GlobalKey<_FeatureReadNavigatorState>(),
    ),
    onVisibleSnapshot: (snapshot, title) {
      if (_openedFeature == feature &&
          _visiblePage.value != (snapshot, title)) {
        _visiblePage.value = (snapshot, title);
      }
    },
    snapshot: widget.snapshots[feature]!,
    cacheEpoch: widget.readCacheEpoch,
    businessCacheEpoch: widget.businessCacheEpoch,
    onExit: () => setState(() => _openedFeature = null),
    onRetry: () => widget.onRetryFeature(feature),
    onQuery: widget.onFeatureQuery == null
        ? null
        : (query) => widget.onFeatureQuery!(feature, query),
    pageBuilder: (page) => _FeatureDetailView(
      key: page.pageKey,
      isLanding: page.isLanding,
      visible: _openedFeature == feature && page.isCurrent,
      onLoadAllGrades: widget.onLoadAllGrades,
      onGradeRoutes: (routes) {
        if (_openedFeature != FeatureId.grades ||
            !page.isCurrent ||
            (routes.length == _gradesReadRoutes.length &&
                routes.entries.every(
                  (e) => _gradesReadRoutes[e.key] == e.value,
                )))
          return;
        setState(() => _gradesReadRoutes = Map.unmodifiable(routes));
      },
      isBykcChosenDetail: page.isBykcChosenDetail,
      onOpenBykcChosen: page.onOpenBykcChosen,
      ygdkRecordsReadback: widget.ygdkRecordsReadback,
      reminderSettings: _reminderSettings,
      reminderError: _reminderError,
      onReminderChanged: widget.onSaveYgdkReminder == null
          ? null
          : _setReminderEnabled,
      feature: feature,
      snapshot: page.snapshot,
      query: page.query,
      backLabel: page.backLabel,
      onBack: page.onBack,
      onRetry: page.onRetry,
      onQuery: page.onQuery,
      onNavigate: page.onNavigate,
      onLoadAcademicTerms: widget.onLoadAcademicTerms,
      onLoadAcademicWeeks: widget.onLoadAcademicWeeks,
      scheduleImports: widget.scheduleImports,
      onSaveScheduleSemester: widget.onSaveScheduleSemester,
      onCancelScheduleImport: widget.onCancelScheduleImport,
      onLoadCgyyPurposes: widget.onLoadCgyyPurposes,
      onFormRouteOptions: (routes) => _showRouteOptions(
        context,
        routes.values.toSet().length == 1 ? routes.values.first : null,
        homeRoutes: routes,
      ),
      onScheduleTitle: page.onScheduleTitle,
      readCacheEpoch: widget.readCacheEpoch + widget.businessCacheEpoch,
      onBykcWrite: !_hasWriteCommands || widget.onPrepareBykcWrite == null
          ? null
          : _startBykcWrite,
      onBykcSignWrite:
          !_hasWriteCommands || widget.onPrepareBykcSignWrite == null
          ? null
          : _startBykcSignWrite,
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
      onCaptureYgdkPhoto: _hasYgdkSubmissionCapabilities
          ? widget.onCaptureYgdkPhoto
          : null,
      onPickYgdkPhoto: _hasYgdkSubmissionCapabilities
          ? widget.onPickYgdkPhoto
          : null,
    ),
  );

  Widget _buildTab(BuildContext context) => _utilityPage != null
      ? _utilityPage == '关于'
            ? _AboutView(
                loadVersion: widget.onLoadAppVersion,
                openLink: widget.onOpenAppLink,
              )
            : _buildProfile()
      : switch (_selectedIndex) {
          0 => _HomeView(
            user: widget.user,
            snapshots: widget.homeSnapshots ?? widget.snapshots,
            visible: _openedFeature == null && widget.writeState.intent == null,
            cacheEpoch: widget.readCacheEpoch,
            businessCacheEpoch: widget.businessCacheEpoch,
            onLoadSupplement: widget.onLoadHomeSupplement,
            onTodoTap: _openHomeTodo,
            gradeScoreNotice: widget.gradeScoreNotice,
            gradeCheckRoute: widget.gradeCheckRoute,
            onCheckGradeUpdates: widget.onCheckGradeUpdates,
            onOpenGradeNotice: _openGradeNotice,
            onDismissGradeNotice: widget.onConsumeGradeNotice,
            onSignin: _hasWriteCommands && widget.onPrepareSigninWrite != null
                ? _startSigninWrite
                : null,
            reminderSettings: _reminderSettings,
            onObserveProgress: _observeHomeProgress,
            onRoutes: (routes) {
              if (routes.length == _homeReadRoutes.length &&
                  routes.entries.every(
                    (e) => _homeReadRoutes[e.key] == e.value,
                  ))
                return;
              setState(() => _homeReadRoutes = Map.unmodifiable(routes));
            },
            onFeatureTap: (feature) => setState(() => _openedFeature = feature),
            onRetryFeature: widget.onRetryFeature,
            onRefresh: widget.onRefresh,
          ),
          1 => _FeatureGridView(
            snapshots: widget.snapshots,
            onFeatureTap: (feature) => setState(() => _openedFeature = feature),
            onRetryFeature: widget.onRetryFeature,
          ),
          2 => _AdvancedFeaturesView(
            snapshots: widget.snapshots,
            onFeatureTap: (feature) => setState(() => _openedFeature = feature),
            onRetryFeature: widget.onRetryFeature,
          ),
          _ => const SizedBox.shrink(),
        };

  Widget _buildProfile() => _ProfileView(
    cacheAccountId: widget.cacheAccountId,
    canClearBusinessCache: widget.canClearBusinessCache,
    onReadCacheUsage: widget.onReadCacheUsage,
    onClearBusinessCache: widget.onClearBusinessCache,
    settingsOnly: _utilityPage == '设置',
    user: widget.user,
    routePolicy: widget.routePolicy,
    telemetryEnabled: widget.telemetryEnabled,
    onRoutePolicyChanged: widget.onRoutePolicyChanged,
    onTelemetryChanged: widget.onTelemetryChanged,
    onLogout: widget.onLogout,
    onLogoutAndClearAccount: widget.onLogoutAndClearAccount,
    activeRoutes: widget.activeRoutes,
    onReadDiagnostics: widget.onReadDiagnostics,
    themeMode: widget.themeMode,
    onThemeModeChanged: widget.onThemeModeChanged,
  );

  Widget _buildRail(BuildContext context) {
    final extended = MediaQuery.sizeOf(context).width >= 1000;
    return NavigationRail(
      scrollable: true,
      minWidth: 80,
      minExtendedWidth: 200,
      selectedIndex: _selectedIndex,
      onDestinationSelected: _selectTab,
      extended: extended,
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.selected,
      leading: _buildRailLeading(context, extended),
      destinations: _tabs
          .map(
            (tab) => NavigationRailDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: Text(tab.label),
            ),
          )
          .toList(),
    );
  }

  Widget _buildRailLeading(BuildContext context, bool extended) {
    final theme = Theme.of(context);
    final iconWidget = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/icons/app_icon.png',
        package: 'ubaa_ui',
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => CircleAvatar(
          radius: 18,
          child: Text((widget.user?.preferredName ?? 'U').characters.first),
        ),
      ),
    );

    final name = widget.user?.preferredName ?? '用户';
    final username = widget.user?.username ?? '';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (widget.writeState.intent != null) return;
        setState(() {
          _openedFeature = null;
          _utilityPage = '我的资料';
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: extended
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  iconWidget,
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (username.isNotEmpty && username != name) ...[
                          const SizedBox(height: 2),
                          Text(
                            username,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              )
            : iconWidget,
      ),
    );
  }

  Drawer _buildDrawer(BuildContext context) => Drawer(
    child: SafeArea(
      child: Column(
        children: <Widget>[
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
            ),
            accountName: Text(
              widget.user?.preferredName ?? 'UBAA',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            accountEmail: Text(
              widget.user?.username == widget.user?.preferredName
                  ? ''
                  : widget.user?.username ?? '',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            currentAccountPicture: CircleAvatar(
              child: Text((widget.user?.preferredName ?? 'U').characters.first),
            ),
          ),
          for (final item in [
            ('我的资料', Icons.person_outline),
            ('设置', Icons.settings_outlined),
            ('关于', Icons.info_outline),
          ])
            ListTile(
              leading: Icon(item.$2),
              title: Text(item.$1),
              onTap: () {
                Navigator.of(context).pop();
                if (widget.writeState.intent != null) return;
                setState(() {
                  _openedFeature = null;
                  _utilityPage = item.$1;
                });
              },
            ),
        ],
      ),
    ),
  );

  void _selectTab(int index) {
    if (widget.writeState.intent != null) return;
    setState(() {
      _selectedIndex = index;
      _utilityPage = null;
      _openedFeature = null;
    });
  }

  Future<void> _showRouteOptions(
    BuildContext context,
    ConnectionMode? route, {
    Map<String, ConnectionMode>? homeRoutes,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('连接路线'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前页面：${homeRoutes != null && homeRoutes.values.toSet().length > 1 ? '直连与WebVPN' : route?.label ?? '未确定'}',
              ),
              if (homeRoutes != null) ...[
                const SizedBox(height: 8),
                for (final entry in homeRoutes.entries)
                  Text('${entry.key}：${entry.value.label}'),
              ],
              const SizedBox(height: 8),
              const Text('实际路线以当前显示的读取结果为准。切换默认策略后，下次读取使用新策略；已显示的结果不会被改写。'),
              const SizedBox(height: 16),
              DropdownButton<RoutePolicy>(
                value: widget.routePolicy,
                isExpanded: true,
                items: RoutePolicy.values
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.label),
                      ),
                    )
                    .toList(),
                onChanged: widget.writeState.intent != null
                    ? null
                    : (value) {
                        if (value == null) return;
                        Navigator.of(context).pop();
                        widget.onRoutePolicyChanged(value);
                      },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

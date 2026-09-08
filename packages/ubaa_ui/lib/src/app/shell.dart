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
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.readCacheEpoch = 0,
    this.onLoadAcademicTerms,
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
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  /// 应用读取生命周期改变时使父返回缓存失效，当前页面草稿仍由页面持有。
  final int readCacheEpoch;

  /// 用户打开学期选择器后读取独立选项，不改写课表结果页。
  final Future<FeatureResult> Function(bool forceRefresh)? onLoadAcademicTerms;
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
  }

  @override
  void didUpdateWidget(covariant UbaaMainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user?.username != widget.user?.username) {
      _accountGeneration++;
      _visitedFeatures.clear();
      _readPageKeys.clear();
      _openedFeature = null;
      _utilityPage = null;
      _visiblePage.value = null;
    }
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
            intent: pendingWrite,
            onCancel: _cancelWrite,
            onConfirm: _confirmWrite,
            isSubmitting: widget.writeState.isSubmitting,
            isDiscarding: widget.writeState.isDiscarding,
            error: widget.writeState.error,
          ),
      ],
    );
    return Scaffold(
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
          ),
        ),
        leading: pendingWrite != null
            ? null
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
              final route =
                  pendingWrite?.resolvedRoute ??
                  (_openedFeature == snapshot?.feature
                      ? snapshot?.resolvedRoute
                      : null);
              return IconButton(
                tooltip: '实际路线：${route?.label ?? '未确定'}',
                icon: Icon(
                  route == ConnectionMode.direct
                      ? Icons.lan_outlined
                      : route == ConnectionMode.webvpn
                      ? Icons.vpn_lock_outlined
                      : Icons.route_outlined,
                ),
                onPressed: () => _showRouteOptions(context, route),
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
              onPressed: () =>
                  _readPageKeys[_openedFeature]?.currentState?.refreshCurrent(),
              icon: const Icon(Icons.refresh),
            ),
          if (_openedFeature == null &&
              _utilityPage == null &&
              _selectedIndex == 0)
            IconButton(
              tooltip: '刷新',
              onPressed: () => widget.onRefresh(),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      drawer: _buildDrawer(context),
      // 保持内容父层级与 key 稳定，宽窄切换不销毁已访问页面。
      body: Row(
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
    onExit: () => setState(() => _openedFeature = null),
    onRetry: () => widget.onRetryFeature(feature),
    onQuery: widget.onFeatureQuery == null
        ? null
        : (query) => widget.onFeatureQuery!(feature, query),
    pageBuilder: (page) => _FeatureDetailView(
      key: page.pageKey,
      isLanding: page.isLanding,
      isBykcChosenDetail: page.isBykcChosenDetail,
      onOpenBykcChosen: page.onOpenBykcChosen,
      feature: feature,
      snapshot: page.snapshot,
      query: page.query,
      backLabel: page.backLabel,
      onBack: page.onBack,
      onRetry: page.onRetry,
      onQuery: page.onQuery,
      onNavigate: page.onNavigate,
      onLoadAcademicTerms: widget.onLoadAcademicTerms,
      readCacheEpoch: widget.readCacheEpoch,
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
      onPickYgdkPhoto: _hasYgdkSubmissionCapabilities
          ? widget.onPickYgdkPhoto
          : null,
    ),
  );

  Widget _buildTab(BuildContext context) => _utilityPage != null
      ? _buildProfile()
      : switch (_selectedIndex) {
          0 => _HomeView(
            user: widget.user,
            snapshots: widget.snapshots,
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

  Widget _buildRail(BuildContext context) => NavigationRail(
    scrollable: true,
    minWidth: 80,
    minExtendedWidth: 200,
    selectedIndex: _selectedIndex,
    onDestinationSelected: _selectTab,
    extended: MediaQuery.sizeOf(context).width >= 1000,
    labelType: MediaQuery.sizeOf(context).width >= 1000
        ? NavigationRailLabelType.none
        : NavigationRailLabelType.selected,
    leading: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: CircleAvatar(
        radius: 28,
        child: Text((widget.user?.preferredName ?? 'U').characters.first),
      ),
    ),
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
    ConnectionMode? route,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('连接路线'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前页面：${route?.label ?? '未确定'}'),
            const SizedBox(height: 8),
            const Text('实际路线以当前显示的读取结果为准。切换默认策略后，下次读取使用新策略；已显示的结果不会被改写。'),
            const SizedBox(height: 16),
            DropdownButton<RoutePolicy>(
              value: widget.routePolicy,
              isExpanded: true,
              items: RoutePolicy.values
                  .map(
                    (item) =>
                        DropdownMenuItem(value: item, child: Text(item.label)),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _startBykcWrite(WriteOperation operation, int courseId) async {
    final prepare = widget.onPrepareBykcWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(operation, courseId),
      expectedOperation: operation,
      failureMessage: '暂时无法准备操作；尚未提交任何写请求。',
    );
  }

  Future<void> _startBykcSignWrite(BykcSignAction action) async {
    final prepare = widget.onPrepareBykcSignWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(action),
      failureMessage: '暂时无法准备博雅签到；尚未提交任何写请求。',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startSigninWrite(SigninPerformAction action) async {
    final prepare = widget.onPrepareSigninWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(action),
      failureMessage: '暂时无法准备签到；尚未提交任何写请求。',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startCgyyCancelWrite(CgyyCancelAction action) async {
    final prepare = widget.onPrepareCgyyCancelWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(action),
      failureMessage: '暂时无法准备取消研讨室订单；尚未提交任何写请求。',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startLibbookReserveWrite(LibbookReserveAction action) async {
    final prepare = widget.onPrepareLibbookReserveWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(action),
      failureMessage: '暂时无法准备图书馆预约；尚未提交任何写请求。',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startLibbookCancelWrite(LibbookCancelAction action) async {
    final prepare = widget.onPrepareLibbookCancelWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(action),
      failureMessage: '暂时无法准备取消图书馆预约；尚未提交任何写请求。',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startEvaluation(List<EvaluationSubmitTarget> targets) async {
    final prepare = widget.onPrepareEvaluationWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(targets),
      failureMessage: '暂时无法准备教学评教；尚未提交任何写请求。',
      expectedOperation: WriteOperation.evaluationSubmitCourses,
    );
  }

  Future<void> _startYgdkSubmitWrite(YgdkSubmitInput input) async {
    final prepare = widget.onPrepareYgdkSubmitWrite;
    if (!_hasYgdkSubmissionCapabilities || prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(input),
      failureMessage: '暂时无法准备阳光打卡；尚未提交任何写请求。',
      expectedOperation: WriteOperation.ygdkSubmit,
    );
  }

  Future<void> _startCgyySubmitWrite(CgyySubmitInput input) async {
    final prepare = widget.onPrepareCgyySubmitWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(input),
      failureMessage: '暂时无法准备研讨室预约；尚未提交任何写请求。',
      expectedOperation: WriteOperation.cgyySubmitReservation,
    );
  }

  Future<void> _prepareWrite({
    required Future<WriteIntent> Function() prepare,
    required String failureMessage,
    required WriteOperation expectedOperation,
  }) async {
    final run = widget.onRunWritePrepare;
    if (!_hasWriteCommands || run == null || widget.writeState.isSubmitting) {
      return;
    }
    try {
      await run(prepare, expectedOperation: expectedOperation);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  Future<void> _cancelWrite() async {
    final cancel = widget.onCancelWrite;
    if (cancel == null || widget.writeState.isSubmitting) return;
    try {
      await cancel();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时无法取消待确认操作，请重试。')));
    }
  }

  Future<void> _confirmWrite() async {
    final intent = widget.writeState.intent;
    if (intent == null || widget.writeState.isSubmitting) return;
    if (intent.operation == WriteOperation.ygdkSubmit &&
        !_hasYgdkSubmissionCapabilities) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('阳光打卡能力不完整；尚未提交任何写请求。')));
      return;
    }
    final confirm = widget.onConfirmWrite;
    if (confirm == null) return;
    final outcome = await confirm();
    if (!mounted || outcome == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(outcome.message)));
  }
}

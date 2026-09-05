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
    this.activeRoutes = const <ConnectionMode>[],
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
  final List<ConnectionMode> activeRoutes;
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

  /// 在 [onWriteSuccess] 刷新场馆订单后，用提交收据匹配只读订单编号。
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
  final Map<FeatureId, FeatureQuery> _featureQueries =
      <FeatureId, FeatureQuery>{};

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

  static const _tabs = <({String label, IconData icon, IconData selectedIcon})>[
    (label: '主页', icon: Icons.home_outlined, selectedIcon: Icons.home),
    (label: '普通功能', icon: Icons.apps_outlined, selectedIcon: Icons.apps),
    (
      label: '高级功能',
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
    ),
    (label: '我的', icon: Icons.person_outline, selectedIcon: Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final pendingWrite = widget.writeState.intent;
    final body = pendingWrite != null
        ? WriteConfirmationView(
            intent: pendingWrite,
            onCancel: _cancelWrite,
            onConfirm: _confirmWrite,
            isSubmitting: widget.writeState.isSubmitting,
            isDiscarding: widget.writeState.isDiscarding,
            error: widget.writeState.error,
          )
        : _openedFeature == null
        ? _buildTab(context)
        : _FeatureDetailView(
            feature: _openedFeature!,
            snapshot: widget.snapshots[_openedFeature!]!,
            query: _featureQueries[_openedFeature!] ?? const FeatureQuery(),
            onBack: () => setState(() => _openedFeature = null),
            onRetry: () {
              final feature = _openedFeature!;
              final query = _featureQueries[feature];
              return query == null || widget.onFeatureQuery == null
                  ? widget.onRetryFeature(feature)
                  : widget.onFeatureQuery!(feature, query);
            },
            onQuery: widget.onFeatureQuery == null
                ? null
                : (query) {
                    final feature = _openedFeature!;
                    _featureQueries[feature] = query;
                    return widget.onFeatureQuery!(feature, query);
                  },
            onBykcWrite: !_hasWriteCommands || widget.onPrepareBykcWrite == null
                ? null
                : _startBykcWrite,
            onBykcSignWrite:
                !_hasWriteCommands || widget.onPrepareBykcSignWrite == null
                ? null
                : _startBykcSignWrite,
            onSigninWrite:
                !_hasWriteCommands || widget.onPrepareSigninWrite == null
                ? null
                : _startSigninWrite,
            onCgyyCancelWrite:
                !_hasWriteCommands || widget.onPrepareCgyyCancelWrite == null
                ? null
                : _startCgyyCancelWrite,
            onLibbookReserveWrite:
                !_hasWriteCommands ||
                    widget.onPrepareLibbookReserveWrite == null
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
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          pendingWrite == null
              ? (_openedFeature?.title ?? _tabs[_selectedIndex].label)
              : '确认${pendingWrite.operation.title}',
        ),
        leading: _openedFeature == null || pendingWrite != null
            ? null
            : IconButton(
                tooltip: '返回',
                onPressed: () => setState(() => _openedFeature = null),
                icon: const Icon(Icons.arrow_back),
              ),
        actions: <Widget>[
          if (_openedFeature == null && _selectedIndex == 0)
            IconButton(
              tooltip: '刷新',
              onPressed: () => widget.onRefresh(),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      drawer: wide ? null : _buildDrawer(context),
      body: wide
          ? Row(
              children: <Widget>[
                _buildRail(context),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
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

  Widget _buildTab(BuildContext context) => switch (_selectedIndex) {
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
    _ => _ProfileView(
      user: widget.user,
      routePolicy: widget.routePolicy,
      telemetryEnabled: widget.telemetryEnabled,
      onRoutePolicyChanged: widget.onRoutePolicyChanged,
      onTelemetryChanged: widget.onTelemetryChanged,
      onLogout: widget.onLogout,
      onLogoutAndClearAccount: widget.onLogoutAndClearAccount,
      activeRoutes: widget.activeRoutes,
    ),
  };

  Widget _buildRail(BuildContext context) => NavigationRail(
    selectedIndex: _selectedIndex,
    onDestinationSelected: _selectTab,
    extended: MediaQuery.sizeOf(context).width >= 1100,
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
            accountName: Text(widget.user?.preferredName ?? 'UBAA'),
            accountEmail: Text(widget.user?.username ?? ''),
            currentAccountPicture: CircleAvatar(
              child: Text((widget.user?.preferredName ?? 'U').characters.first),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _tabs.length,
              itemBuilder: (context, index) => ListTile(
                selected: _selectedIndex == index,
                leading: Icon(
                  _selectedIndex == index
                      ? _tabs[index].selectedIcon
                      : _tabs[index].icon,
                ),
                title: Text(_tabs[index].label),
                onTap: () {
                  Navigator.of(context).pop();
                  _selectTab(index);
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _selectTab(int index) {
    if (widget.writeState.intent != null) return;
    setState(() {
      _selectedIndex = index;
      _openedFeature = null;
    });
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
      failureMessage: '暂时无法准备取消场馆订单；尚未提交任何写请求。',
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
      failureMessage: '暂时无法准备场馆预约；尚未提交任何写请求。',
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

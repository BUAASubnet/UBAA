import 'dart:async';
import '../features/ihome/view.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/write_callbacks.dart';
import '../shared/loading.dart' show RefreshActionButton;
import '../features/cgyy/reservation_flow.dart' show CgyySlotLegend;
import '../shared/feedback.dart';
import '../shared/refresh.dart' show PullToRefresh;
import '../shared/scroll_gutters.dart' show ScrollGutters;
import 'about.dart' show AboutView;
import 'home.dart' show FeatureGridView, HomeView;
import 'destination.dart';
import '../theme.dart';
import 'profile.dart' show ProfileView;
import 'write_readback_notice.dart' show WriteReadbackNotice;
import '../common/feature_detail.dart' show FeatureDetailView;
import '../common/read_navigator.dart'
    show FeatureReadNavigator, FeatureReadNavigatorState;
part 'shell_write.dart';
part 'shell_navigation.dart';
part 'bykc_preferences.dart';
part 'preferences/recent_features.dart';

/// 主界面容器：窄屏使用底部导航，桌面宽屏使用侧边导航。
class UbaaMainShell extends StatefulWidget {
  const UbaaMainShell({
    required this.user,
    required this.snapshots,
    required this.routePolicy,
    required this.telemetryEnabled,
    this.telemetryAvailable = true,
    required this.onRefresh,
    required this.onRetryFeature,
    required this.onLogout,
    required this.onLogoutAndClearAccount,
    required this.onRoutePolicyChanged,
    required this.onTelemetryChanged,
    this.initialDestination = UiDestination.home,
    this.homeClock,
    this.connectionStatus,
    this.writeReadbacks = const [],
    this.writeReadbackError,
    this.onDismissWriteReadback,
    this.onRefreshWriteReadbacks,
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
    this.onLoadCgyyDefaults,
    this.onSaveCgyyDefaults,
    this.onLoadAppVersion,
    this.ihomeService,
    this.onOpenAppLink,
    this.onLoadAllGrades,
    this.gradeScoreNotice,
    this.gradeCheckRoute,
    this.onCheckGradeUpdates,
    this.onConsumeGradeNotice,
    this.ygdkRecordsReadback,
    this.homeSnapshots,
    this.onLoadHomeSupplement,
    this.onLoadHomeDaySchedule,
    this.onLoadYgdkReminder,
    this.onSaveYgdkReminder,
    this.onLoadBykcFilters,
    this.onSaveBykcFilters,
    this.onLoadRecentFeatures,
    this.onSaveRecentFeatures,
    this.activeRoutes = const <ConnectionMode>[],
    this.onReadDiagnostics,
    this.writeState = const WriteState.idle(),
    this.onRunWritePrepare,
    this.onCancelWrite,
    this.onConfirmWrite,
    this.onFeatureQuery,
    this.onOpenLockDisplay,
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

  /// 原生合成日期场景可显式传入时钟，避免引擎帧跨 Zone 丢失测试时间。
  final Clock? homeClock;
  final Map<FeatureId, FeatureSnapshot> snapshots;

  /// 仅用于呈现原协调器已完成的固定路线记录回读，不触发新读取。
  final FeatureSnapshot? ygdkRecordsReadback;
  final Map<FeatureId, FeatureSnapshot>? homeSnapshots;
  final Future<FeatureResult> Function(HomeSupplement source, bool force)?
  onLoadHomeSupplement;
  final Future<FeatureResult> Function(String date, bool force)?
  onLoadHomeDaySchedule;
  final Future<YgdkReminderSettings> Function()? onLoadYgdkReminder;
  final Future<void> Function(YgdkReminderSettings)? onSaveYgdkReminder;
  final Future<BykcCourseFilters?> Function()? onLoadBykcFilters;
  final Future<void> Function(BykcCourseFilters)? onSaveBykcFilters;
  final Future<List<FeatureId>> Function()? onLoadRecentFeatures;
  final Future<void> Function(List<FeatureId>)? onSaveRecentFeatures;
  final RoutePolicy routePolicy;
  final bool telemetryEnabled;
  final bool telemetryAvailable;
  final Future<void> Function() onRefresh;
  final Future<void> Function(FeatureId feature) onRetryFeature;
  final Future<void> Function() onLogout;
  final Future<void> Function() onLogoutAndClearAccount;
  final ValueChanged<RoutePolicy> onRoutePolicyChanged;
  final ValueChanged<bool> onTelemetryChanged;

  /// 供宿主恢复上次导航位置或集成测试从指定功能分组启动。
  final UiDestination initialDestination;
  final String? connectionStatus;
  final List<WriteReadbackHint> writeReadbacks;
  final UiError? writeReadbackError;
  final Future<void> Function(String)? onDismissWriteReadback;
  final Future<void> Function()? onRefreshWriteReadbacks;
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
  final Future<CgyyReservationDefaults?> Function()? onLoadCgyyDefaults;
  final Future<void> Function(CgyyReservationDefaults)? onSaveCgyyDefaults;
  final Future<String?> Function()? onLoadAppVersion;
  final IhomeService? ihomeService;
  final Future<bool> Function(AppLink)? onOpenAppLink;
  final GradesAggregateLoader? onLoadAllGrades;
  final GradeScoreNotice? gradeScoreNotice;
  final ConnectionMode? gradeCheckRoute;
  final Future<void> Function()? onCheckGradeUpdates;
  final VoidCallback? onConsumeGradeNotice;
  final List<ConnectionMode> activeRoutes;

  /// 宿主提供本轮允许字段的脱敏报告，不读取账号或业务数据。
  final String Function()? onReadDiagnostics;
  final Future<CgyyLockDisplaySession> Function()? onOpenLockDisplay;
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
  List<FeatureId> _recentFeatures = [];
  int _recentRevision = 0;
  void _setRecentFeatures(List<FeatureId> value) {
    setState(() => _recentFeatures = value);
  }

  YgdkReminderSettings? _reminderSettings;
  String? _reminderError;
  int _reminderRevision = 0;
  BykcCourseFilters _bykcFilters = const BykcCourseFilters.defaults();
  String? _bykcFilterError;
  int _bykcFilterRevision = 0;
  void _setBykcFilterState(BykcCourseFilters value, String? error) {
    setState(() {
      _bykcFilters = value;
      _bykcFilterError = error;
    });
  }

  late int _selectedIndex;
  FeatureId? _openedFeature;
  String? _utilityPage;
  final _visiblePage = ValueNotifier<(FeatureSnapshot, String)?>(null);
  bool _cgyyOnlyAvailable = true;
  final Set<FeatureId> _visitedFeatures = <FeatureId>{};
  int _accountGeneration = 0;
  int _lockRefreshRevision = 0;
  final Map<FeatureId, GlobalKey<FeatureReadNavigatorState>> _readPageKeys = {};
  bool _homeSigninActive = false;
  // 一点即完成的写操作进行中；期间忽略其他写入点击。
  WriteOperation? _directWriteActive;
  void _setDirectWriteActive(WriteOperation? operation) =>
      setState(() => _directWriteActive = operation);
  (WriteOperation, int)? _bykcWriteActive;
  void _setBykcWriteActive((WriteOperation, int)? action) =>
      setState(() => _bykcWriteActive = action);
  void _setHomeSigninActive(bool active) =>
      setState(() => _homeSigninActive = active);

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialDestination.index;
    unawaited(_loadReminderSettings());
    unawaited(_loadBykcFilters());
    unawaited(_loadRecentFeatures());
  }

  @override
  void didUpdateWidget(covariant UbaaMainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final accountChanged =
        (oldWidget.user?.accountScope ?? oldWidget.user?.username) !=
        (widget.user?.accountScope ?? widget.user?.username);
    if (accountChanged ||
        oldWidget.routePolicy != widget.routePolicy ||
        oldWidget.businessCacheEpoch != widget.businessCacheEpoch) {
      _refreshes.clear();
      _readPageKeys[FeatureId.bykc]?.currentState?.cancelBykcCourseWrite();
    }
    if (accountChanged) {
      _accountGeneration++;
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
    // 学校标识变化只重新绑定偏好，不改变既有资料页的导航行为。
    if (accountChanged || oldWidget.user?.schoolId != widget.user?.schoolId) {
      _recentRevision++;
      _recentFeatures = [];
      unawaited(_loadRecentFeatures());
      _bykcFilters = const BykcCourseFilters.defaults();
      _bykcFilterError = null;
      _bykcFilterRevision++;
      unawaited(_loadBykcFilters());
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

  void _openFeatureList(FeatureId feature) {
    final generation = _accountGeneration;
    setState(() => _openedFeature = feature);
    _recordFeatureVisit(feature);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          generation == _accountGeneration &&
          _openedFeature == feature) {
        _readPageKeys[feature]?.currentState?.openList();
      }
    });
  }

  void _openHomeNavigation(FeatureReadNavigation target) {
    final generation = _accountGeneration;
    setState(() => _openedFeature = target.feature);
    _recordFeatureVisit(target.feature);
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

  static const _tabs = UiDestination.values;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    const maxContentWidth = UbaaTheme.pageMaxWidth;
    if (_openedFeature case final feature?) _visitedFeatures.add(feature);
    final pages = _visitedFeatures.toList(growable: false);
    // 只保留已访问页面的 State；每次 build 都读取当前快照和回调。
    final body = IndexedStack(
      key: ValueKey<int>(_accountGeneration),
      index: _openedFeature == null ? 0 : pages.indexOf(_openedFeature!) + 1,
      children: <Widget>[
        TickerMode(enabled: _openedFeature == null, child: _buildTab(context)),
        for (final feature in pages)
          TickerMode(
            key: ValueKey<FeatureId>(feature),
            enabled: _openedFeature == feature,
            // 页面状态继续保留，但提示浮层不能随停用的 ticker 冻结在其他页面。
            child: TooltipVisibility(
              visible: _openedFeature == feature,
              child: _buildFeaturePage(feature),
            ),
          ),
      ],
    );
    // 手机用下拉刷新；桌面鼠标无法下拉，保留按钮与快捷键。
    final touchRefresh = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    final refreshPage = _openedFeature != null
        ? () => _refreshFeature(_openedFeature!)
        : _utilityPage == null && _selectedIndex == 0
        ? _refreshHome
        : null;
    final header = AppBar(
      centerTitle: false,
      toolbarHeight: wide ? 80 : 64,
      automaticallyImplyLeading: !wide,
      titleSpacing: wide && _openedFeature == null && _utilityPage == null
          ? UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width)
          : null,
      title: ValueListenableBuilder<(FeatureSnapshot, String)?>(
        valueListenable: _visiblePage,
        builder: (context, page, _) => Text(
          _openedFeature == FeatureId.schedule
              ? '课表'
              : _openedFeature != null
              ? (page?.$1.feature == _openedFeature
                    ? page!.$2
                    : _openedFeature!.title)
              : (_utilityPage ??
                    (_selectedIndex == 0 ? '首页' : _tabs[_selectedIndex].label)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      leading: _openedFeature != null || _utilityPage != null
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
        if (widget.connectionStatus != null)
          IconButton(
            tooltip: widget.onCompleteLogin != null ? '完成登录' : '连接状态',
            icon: Icon(
              widget.onCompleteLogin != null
                  ? Icons.person_outline
                  : Icons.cloud_off_outlined,
            ),
            onPressed: () async {
              if (widget.onCompleteLogin != null) {
                widget.onCompleteLogin!(context);
                return;
              }
              final retry = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('连接状态'),
                  content: Text(widget.connectionStatus ?? '连接已恢复'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭'),
                    ),
                    if (widget.onReconnect != null)
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('重试'),
                      ),
                  ],
                ),
              );
              if (retry == true && mounted) widget.onReconnect?.call();
            },
          ),
        if (_openedFeature == FeatureId.cgyy)
          ValueListenableBuilder<(FeatureSnapshot, String)?>(
            valueListenable: _visiblePage,
            builder: (context, page, _) => page?.$2 != '预约研讨室'
                ? const SizedBox.shrink()
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilterChip(
                        key: const ValueKey('cgyy-only-available'),
                        label: const Text('只看可预约'),
                        selected: _cgyyOnlyAvailable,
                        visualDensity: VisualDensity.compact,
                        onSelected: (value) =>
                            setState(() => _cgyyOnlyAvailable = value),
                      ),
                      PopupMenuButton<void>(
                        tooltip: '图例',
                        icon: const Icon(Icons.info_outline),
                        itemBuilder: (_) => [
                          const PopupMenuItem<void>(
                            // 点按即关闭；保持可用状态以免图例颜色被调淡。
                            child: CgyySlotLegend(),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        if (_openedFeature == FeatureId.schedule)
          // 文字按钮比日历图标更不易被误认为“选日期”。
          Tooltip(
            message: '选择学期',
            child: TextButton.icon(
              onPressed: () => _readPageKeys[FeatureId.schedule]?.currentState
                  ?.selectScheduleTerm(),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_drop_down),
              label: const Text('学期'),
            ),
          ),
        if (!touchRefresh && _openedFeature != null)
          RefreshActionButton(
            key: ValueKey(_openedFeature),
            tooltip:
                _openedFeature == FeatureId.schedule &&
                    widget.onSaveScheduleSemester != null
                ? '刷新'
                : '刷新当前查询',
            onRefresh: () => _refreshFeature(_openedFeature!),
          ),
        if (!touchRefresh &&
            _openedFeature == null &&
            _utilityPage == null &&
            _selectedIndex == 0)
          RefreshActionButton(
            key: const ValueKey('home-refresh'),
            tooltip: '刷新',
            onRefresh: _refreshHome,
          ),
      ],
    );
    final shell = PopScope<void>(
      canPop: _openedFeature == null && _utilityPage == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_utilityPage != null) {
            setState(() => _utilityPage = null);
          } else {
            _readPageKeys[_openedFeature]?.currentState?.goBack();
          }
        }
      },
      child: Scaffold(
        drawer: !wide ? _buildDrawer(context) : null,
        // 保持内容父层级与 key 稳定，宽窄切换不销毁已访问页面。
        body: Row(
          children: <Widget>[
            if (wide) _buildRail(context),

            Expanded(
              key: const ValueKey<String>('feature-pages'),
              child: Column(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxContentWidth),
                      child: header,
                    ),
                  ),
                  Expanded(
                    child: ScrollGutters(
                      maxWidth: maxContentWidth,
                      child: SafeArea(top: false, bottom: wide, child: body),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : _CompactNavigationBar(
                child: NavigationBar(
                  height:
                      56 +
                      (MediaQuery.textScalerOf(context).scale(12) - 12) * 3,
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
      ),
    );
    if (touchRefresh || refreshPage == null) return shell;
    void refresh() => unawaited(refreshPage());
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): refresh,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): refresh,
      },
      child: Focus(autofocus: true, child: shell),
    );
  }

  final _refreshes = <Object, Future<void>>{};

  Future<void> _joinRefresh(Object key, Future<void> Function() action) {
    final pending = _refreshes[key];
    if (pending != null) return pending;
    late final Future<void> refresh;
    refresh = Future<void>.sync(action).whenComplete(() {
      if (identical(_refreshes[key], refresh)) _refreshes.remove(key);
    });
    _refreshes[key] = refresh;
    return refresh;
  }

  Future<void> _refreshHome() => _joinRefresh('home', widget.onRefresh);

  Future<void> _refreshFeature(FeatureId feature) =>
      _joinRefresh(feature, () async {
        final page = _readPageKeys[feature]?.currentState;
        if (feature == FeatureId.cgyy &&
            page?.currentFrame.query?.view == FeatureQueryView.cgyyLockCode) {
          setState(() => _lockRefreshRevision++);
        } else if (feature == FeatureId.schedule &&
            widget.onSaveScheduleSemester != null &&
            (page?.currentFrame.query?.term?.trim().isNotEmpty ?? false)) {
          await widget.onSaveScheduleSemester!(page!.currentFrame.query!.term!);
        } else {
          await page?.refreshCurrent();
        }
      });

  Widget _buildFeaturePage(FeatureId feature) => FeatureReadNavigator(
    key: _readPageKeys.putIfAbsent(
      feature,
      () => GlobalKey<FeatureReadNavigatorState>(),
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
        : (query) =>
              feature == FeatureId.cgyy &&
                  query.view == FeatureQueryView.cgyyLockCode
              ? Future<void>.value()
              : widget.onFeatureQuery!(feature, query),
    pageBuilder: (page) => PullToRefresh(
      onRefresh: () => _refreshFeature(feature),
      enabled:
          _openedFeature == feature &&
          page.isCurrent &&
          widget.writeState.intent == null &&
          !(feature == FeatureId.cgyy &&
              page.query?.view == FeatureQueryView.cgyyLockCode),
      child: FeatureDetailView(
        key: page.pageKey,
        isLanding: page.isLanding,
        onOpenLockDisplay: widget.onOpenLockDisplay,
        lockRefreshRevision: _lockRefreshRevision,
        visible: _openedFeature == feature && page.isCurrent,
        onLoadAllGrades: widget.onLoadAllGrades,
        isBykcChosenDetail: page.isBykcChosenDetail,
        bykcListCourse: page.bykcListCourse,
        bykcPendingCourseId: _bykcWriteActive?.$2,
        writeBusy: _directWriteActive != null,
        onOpenBykcChosen: page.onOpenBykcChosen,
        bykcFilters: _bykcFilters,
        bykcFilterError: _bykcFilterError,
        onBykcFiltersChanged: (value) => unawaited(_saveBykcFilters(value)),
        ygdkRecordsReadback: widget.ygdkRecordsReadback,
        reminderSettings: _reminderSettings,
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
        onLoadAcademicTerms: widget.onLoadAcademicTerms,
        onLoadAcademicWeeks: widget.onLoadAcademicWeeks,
        scheduleImports: widget.scheduleImports,
        onSaveScheduleSemester: widget.onSaveScheduleSemester,
        onCancelScheduleImport: widget.onCancelScheduleImport,
        onLoadCgyyPurposes: widget.onLoadCgyyPurposes,
        onLoadCgyyDefaults: widget.onLoadCgyyDefaults,
        cgyyOnlyAvailable: _cgyyOnlyAvailable,
        onCgyyShowAll: () => setState(() => _cgyyOnlyAvailable = false),
        onSaveCgyyDefaults: widget.onSaveCgyyDefaults,
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
    ),
  );

  Widget _buildTab(BuildContext context) => _utilityPage != null
      ? _utilityPage == 'iHome'
            ? IhomeView(
                key: ValueKey(
                  widget.cacheAccountId ?? widget.user?.accountScope,
                ),
                service: widget.ihomeService,
              )
            : _utilityPage == '关于'
            ? AboutView(
                loadVersion: widget.onLoadAppVersion,
                openLink: widget.onOpenAppLink,
              )
            : _buildProfile()
      : switch (_selectedIndex) {
          0 => HomeView(
            homeClock: widget.homeClock,
            recentFeatures: _recentFeatures,
            user: widget.user,
            snapshots: widget.homeSnapshots ?? widget.snapshots,
            visible: _openedFeature == null && widget.writeState.intent == null,
            cacheEpoch: widget.readCacheEpoch,
            businessCacheEpoch: widget.businessCacheEpoch,
            onLoadSupplement: widget.onLoadHomeSupplement,
            onLoadDaySchedule: widget.onLoadHomeDaySchedule,
            onTodoTap: _openHomeTodo,
            writeReadbackNotice:
                widget.writeReadbacks.isEmpty &&
                    widget.writeReadbackError == null
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
                      setState(() => _openedFeature = feature);
                      _recordFeatureVisit(feature);
                    },
                  ),
            gradeScoreNotice: widget.gradeScoreNotice,
            gradeCheckRoute: widget.gradeCheckRoute,
            onCheckGradeUpdates: widget.onCheckGradeUpdates,
            onOpenGradeNotice: _openGradeNotice,
            onDismissGradeNotice: widget.onConsumeGradeNotice,
            onSignin: _hasWriteCommands && widget.onPrepareSigninWrite != null
                ? _performHomeSignin
                : null,
            reminderSettings: _reminderSettings,
            onObserveProgress: _observeHomeProgress,
            onFeatureTap: _openFeatureList,
            onRetryFeature: widget.onRetryFeature,
            onRefresh: _refreshHome,
          ),
          1 || 2 || 3 => FeatureGridView(
            onOpenIhome: _selectedIndex == UiDestination.campus.index
                ? () => _openUtility('iHome')
                : null,
            features: _tabs[_selectedIndex].features,
            snapshots: widget.snapshots,
            onFeatureTap: _openFeatureList,
            onRetryFeature: widget.onRetryFeature,
          ),
          4 => _buildProfile(),
          _ => const SizedBox.shrink(),
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
    onOpenProfile: () => _openUtility('我的资料'),
    onOpenAbout: () => _openUtility('关于'),
    user: widget.user,
    routePolicy: widget.routePolicy,
    telemetryEnabled: widget.telemetryEnabled,
    telemetryAvailable: widget.telemetryAvailable,
    onRoutePolicyChanged: widget.onRoutePolicyChanged,
    onTelemetryChanged: widget.onTelemetryChanged,
    onLogout: widget.onLogout,
    onLogoutAndClearAccount: widget.onLogoutAndClearAccount,
    activeRoutes: widget.activeRoutes,
    onReadDiagnostics: widget.onReadDiagnostics,
    themeMode: widget.themeMode,
    onThemeModeChanged: widget.onThemeModeChanged,
  );

  void _openUtility(String page) {
    if (widget.writeState.intent != null) return;
    if (page == UiDestination.settings.label) {
      _selectTab(UiDestination.settings.index);
      return;
    }
    setState(() {
      _openedFeature = null;
      _utilityPage = page;
    });
  }

  void _selectTab(int index) {
    if (widget.writeState.intent != null) return;
    setState(() {
      _selectedIndex = index;
      _utilityPage = null;
      _openedFeature = null;
    });
  }
}

/// 底栏顶部留白 8pt，底部安全区最多保留 20pt，仍避开 Home 指示条。
class _CompactNavigationBar extends StatelessWidget {
  const _CompactNavigationBar({required this.child});

  static const double _topGap = 8;
  static const double _maxBottomInset = 20;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    return ColoredBox(
      color:
          theme.navigationBarTheme.backgroundColor ??
          theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.only(top: _topGap),
        child: MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(
              bottom: media.padding.bottom > _maxBottomInset
                  ? _maxBottomInset
                  : media.padding.bottom,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

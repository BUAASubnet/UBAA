import 'dart:async';
import '../features/bykc/agenda_conflicts.dart';
import '../shared/layout/rail_identity.dart';
import '../shared/dialogs/confirmation.dart';
import '../shared/layout/connection_status.dart' show UiConnectionStatusButton;
import '../features/bhpan/write_flow.dart';
import '../features/bhpan/view.dart';
import '../features/agenda/view.dart';
import '../features/agenda/format.dart' show campusDate, AgendaAccess;
import '../shared/tab_navigation.dart'
    show TabPager, CompactNavigationBar, currentTabPager;
import '../features/ihome/view.dart';
import '../features/finance/view.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import '../shared/app_bar_slot.dart' show UiAppBarSlot;
import '../shared/layout/page_transition.dart' show UiPageTransition;
import '../shared/loading.dart' show UiBusyRegistry, UiBusyScope;
import '../shared/place_memory.dart' show UiPlaceMemory, UiPlaceKeys;
import 'package:flutter/services.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/write_callbacks.dart';
import '../shared/sync_status.dart'
    show UiSyncStatus, uiIsTouchPlatform, uiOldestUpdate;
import '../shared/feedback.dart';
import '../shared/refresh.dart' show PullToRefresh;
import '../shared/scroll_gutters.dart' show ScrollGutters;
import 'about.dart' show AboutView;
import 'home.dart' show FeatureGridView, HomeView, HomeViewState;
import 'destination.dart';
import '../features/home/shell_helpers.dart';
import '../theme.dart';
import 'account/me.dart' show MeView;
import 'profile.dart' show ProfileView;
import 'app_service/notices.dart' show AppServiceNotices;
import 'app_service/settings.dart' show AppServiceControls;
import 'write_readback_notice.dart' show WriteReadbackNotice;
import '../common/feature_detail.dart' show FeatureDetailView;
import '../common/read_navigator.dart'
    show FeatureReadNavigator, FeatureReadNavigatorState;
import 'account/campus_account_loader.dart';

part 'shell_write.dart';
part 'shell_navigation.dart';

part 'shell_sync.dart';
part 'bykc_preferences.dart';
part 'preferences/recent_features.dart';
part 'preferences/places.dart';

/// 主界面容器：窄屏使用底部导航，桌面宽屏使用侧边导航。
class UbaaMainShell extends StatefulWidget {
  const UbaaMainShell({
    required this.user,
    required this.snapshots,
    required this.routePolicy,
    this.appService,
    this.appNotices,
    required this.onRefresh,
    required this.onRetryFeature,
    required this.onLogout,
    required this.onLogoutAndClearAccount,
    required this.onRoutePolicyChanged,
    this.initialDestination = UiDestination.home,
    this.campusAccountService,
    this.bhpanService,
    this.onPickBhpanFile,
    this.onPickBhpanDownload,
    this.onPreviewBhpanFile,
    this.connecting = false,
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
    this.localPreferencesRevision = 0,
    this.cacheAccountId,
    this.canClearBusinessCache = true,
    this.onReadCacheUsage,
    this.onClearBusinessCache,
    this.onLoadAcademicTerms,
    this.onLoadExamTerms,
    this.onLoadAcademicWeeks,
    this.scheduleImports = const {},
    this.onSaveScheduleSemester,
    this.onCancelScheduleImport,
    this.onLoadCgyyPurposes,
    this.onLoadCgyyDefaults,
    this.onSaveCgyyDefaults,
    this.onLoadAppVersion,
    this.ihomeService,
    this.financeService,
    this.onOpenAppLink,
    this.onLoadAllGrades,
    this.gradeScoreNotice,
    this.gradeCheckRoute,
    this.onConsumeGradeNotice,
    this.ygdkRecordsReadback,
    this.homeState,
    this.onRefreshHome,
    this.onRetryHomeSource,
    this.onHomeReminderChanged,
    this.onHomeVisibilityChanged,
    this.agendaEpoch = 0,
    this.agendaSchoolRoute,
    this.agenda = const AgendaAccess(),
    this.onLoadYgdkReminder,
    this.onSaveYgdkReminder,
    this.onLoadBykcFilters,
    this.onSaveBykcFilters,
    this.placePreferences = const {},
    this.onSavePlacePreference,
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
    this.onReadLockDisplay,
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
  final Clock? homeClock;
  final Map<FeatureId, FeatureSnapshot> snapshots;
  final FeatureSnapshot? ygdkRecordsReadback;
  final HomeState? homeState;
  final ValueChanged<bool>? onHomeVisibilityChanged;
  final Future<void> Function()? onRefreshHome;
  final Future<void> Function(FeatureId)? onRetryHomeSource;
  final ValueChanged<YgdkReminderSettings?>? onHomeReminderChanged;
  final int agendaEpoch;
  final ConnectionMode? agendaSchoolRoute;
  final AgendaAccess agenda;
  final Future<YgdkReminderSettings> Function()? onLoadYgdkReminder;
  final Future<void> Function(YgdkReminderSettings)? onSaveYgdkReminder;
  final Future<BykcCourseFilters?> Function()? onLoadBykcFilters;
  final Future<void> Function(BykcCourseFilters)? onSaveBykcFilters;
  final Map<String, String> placePreferences;
  final Future<void> Function(String key, String value)? onSavePlacePreference;
  final Future<List<FeatureId>> Function()? onLoadRecentFeatures;
  final Future<void> Function(List<FeatureId>)? onSaveRecentFeatures;
  final RoutePolicy routePolicy;
  final AppServiceControls? appService;

  /// 首页的更新与公告横幅；未接入应用服务或无需提示时为 null。
  final AppServiceNotices? appNotices;
  final Future<void> Function() onRefresh;
  final Future<void> Function(FeatureId feature) onRetryFeature;
  final Future<void> Function() onLogout;
  final Future<void> Function() onLogoutAndClearAccount;
  final ValueChanged<RoutePolicy> onRoutePolicyChanged;
  final UiDestination initialDestination;

  final CampusAccountService? campusAccountService;
  final BhpanService? bhpanService;
  final Future<BhpanLocalFile?> Function()? onPickBhpanFile;
  final Future<BhpanDownloadDestination?> Function(String, bool Function())?
  onPickBhpanDownload;

  final Future<BhpanDownloadDestination?> Function(String, bool Function())?
  onPreviewBhpanFile;

  final bool connecting;
  final String? connectionStatus;
  final List<WriteReadbackHint> writeReadbacks;
  final UiError? writeReadbackError;
  final Future<void> Function(String)? onDismissWriteReadback;
  final Future<void> Function()? onRefreshWriteReadbacks;
  final VoidCallback? onReconnect;
  final ValueChanged<BuildContext>? onCompleteLogin;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  final int readCacheEpoch;
  final int businessCacheEpoch;
  final int localPreferencesRevision;
  final String? cacheAccountId;
  final bool canClearBusinessCache;
  final Future<CacheUsageSummary> Function(String)? onReadCacheUsage;
  final Future<CacheClearOutcome> Function(String)? onClearBusinessCache;
  final Future<FeatureResult> Function(bool forceRefresh)? onLoadAcademicTerms;
  final Future<FeatureResult> Function(bool forceRefresh)? onLoadExamTerms;
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

  /// 财务收入只读服务；为空时不显示入口。
  final FinanceService? financeService;
  final Future<bool> Function(AppLink)? onOpenAppLink;
  final GradesAggregateLoader? onLoadAllGrades;
  final GradeScoreNotice? gradeScoreNotice;
  final ConnectionMode? gradeCheckRoute;
  final VoidCallback? onConsumeGradeNotice;
  final List<ConnectionMode> activeRoutes;

  final String Function()? onReadDiagnostics;
  final CgyyLockDisplayOpen? onOpenLockDisplay;
  final CgyyLockDisplayRead? onReadLockDisplay;
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

  final CgyyReceiptVerifier? onVerifyCgyyReceipt;
  final CgyyCancellationVerifier? onVerifyCgyyCancellation;
  final EvaluationSubmissionRefresher? onRefreshEvaluationAfterWrite;
  final YgdkSubmissionRefresher? onRefreshYgdkAfterWrite;

  @override
  State<UbaaMainShell> createState() => _UbaaMainShellState();
}

class _UbaaMainShellState extends State<UbaaMainShell> {
  // 页面内容只随账号、路线策略和明确清理变化；网络请求代次独立推进。
  int _contentEpoch = 0;
  Object get _pageContentScope => (
    widget.cacheAccountId ?? widget.user?.accountScope ?? widget.user?.username,
    widget.routePolicy,
    widget.businessCacheEpoch,
  );
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
  late PageController _tabPager;
  FeatureId? _openedFeature;
  FeatureReadNavigation? _pendingHomeTarget;
  String? _utilityPage;
  final _visiblePage = ValueNotifier<(FeatureSnapshot, String)?>(null);
  final _appBarSlot = ValueNotifier<Map<FeatureId, Widget>>(const {});
  final _pageBusy = UiBusyRegistry();
  late final _places = <String, String>{...widget.placePreferences};
  bool _cgyyOnlyAvailable = true;
  final Set<FeatureId> _visitedFeatures = <FeatureId>{};
  int _accountGeneration = 0;
  final _bhpanModalScope = ValueNotifier<int>(0);
  final _bhpanBack = BhpanBackHandle();
  final _homeKey = GlobalKey<HomeViewState>();

  int _pulling = 0;
  Future<void> _pull(Future<void> Function() refresh) async {
    setState(() => _pulling++);
    try {
      await refresh();
    } finally {
      if (mounted) setState(() => _pulling--);
    }
  }

  late final _campusLoader = CampusAccountLoader(
    service: widget.campusAccountService,
    now: () => (widget.homeClock ?? clock).now(),
    changed: () {
      if (mounted) setState(() {});
    },
  );
  void _changeNavigation(VoidCallback change) => setState(change);
  int _lockRefreshRevision = 0;
  void _refreshLockDisplay() => setState(() => _lockRefreshRevision++);
  final Map<FeatureId, GlobalKey<FeatureReadNavigatorState>> _readPageKeys = {};
  bool _homeSigninActive = false;
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
    _tabPager = PageController(keepPage: false);
    unawaited(_loadReminderSettings());
    unawaited(_loadBykcFilters());
    unawaited(_loadRecentFeatures());
    if (_onMeTab) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => mounted ? _ensureCampusAccountLoaded() : null,
      );
    }
  }

  @override
  void didUpdateWidget(covariant UbaaMainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    Object? account(UbaaMainShell shell) =>
        shell.cacheAccountId ??
        shell.user?.accountScope ??
        shell.user?.username;
    final accountChanged =
        account(oldWidget) != account(widget) ||
        (widget.cacheAccountId == null &&
            widget.user?.accountScope == null &&
            oldWidget.user?.schoolId != null &&
            widget.user?.schoolId != null &&
            oldWidget.user?.schoolId != widget.user?.schoolId);
    final contentChanged =
        accountChanged ||
        oldWidget.routePolicy != widget.routePolicy ||
        oldWidget.businessCacheEpoch != widget.businessCacheEpoch;
    if (contentChanged) _contentEpoch++;
    _updatePlaces(oldWidget, accountChanged);
    if (accountChanged ||
        oldWidget.routePolicy != widget.routePolicy ||
        !identical(oldWidget.bhpanService, widget.bhpanService))
      _bhpanModalScope.value++;
    if (accountChanged ||
        oldWidget.routePolicy != widget.routePolicy ||
        oldWidget.businessCacheEpoch != widget.businessCacheEpoch ||
        !identical(
          oldWidget.campusAccountService,
          widget.campusAccountService,
        )) {
      _resetCampusAccount(keepContent: !contentChanged);
      if (_onMeTab) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => mounted ? _ensureCampusAccountLoaded() : null,
        );
      }
    }
    if (oldWidget.connecting && !widget.connecting && _onMeTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureCampusAccountLoaded();
      });
    }
    if (accountChanged ||
        oldWidget.routePolicy != widget.routePolicy ||
        oldWidget.businessCacheEpoch != widget.businessCacheEpoch) {
      _refreshes.clear();
      _readPageKeys[FeatureId.bykc]?.currentState?.cancelBykcCourseWrite();
    }
    if (accountChanged) {
      _tabPager.dispose();
      _tabPager = PageController(initialPage: _selectedIndex, keepPage: false);
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
    if (accountChanged) {
      _recentRevision++;
      _recentFeatures = [];
      unawaited(_loadRecentFeatures());
      _bykcFilters = const BykcCourseFilters.defaults();
      _bykcFilterError = null;
      _bykcFilterRevision++;
      unawaited(_loadBykcFilters());
    } else if (oldWidget.localPreferencesRevision !=
        widget.localPreferencesRevision) {
      _recentRevision++;
      _bykcFilterRevision++;
      _reminderRevision++;
      unawaited(_loadRecentFeatures());
      unawaited(_loadBykcFilters());
      unawaited(_loadReminderSettings());
    }
  }

  Future<void> _loadReminderSettings() async {
    final generation = _accountGeneration;
    final revision = _reminderRevision;
    final load = widget.onLoadYgdkReminder;
    if (load == null) {
      _reminderSettings = const YgdkReminderSettings();
      widget.onHomeReminderChanged?.call(_reminderSettings);
      return;
    }
    try {
      final value = await load();
      if (mounted &&
          generation == _accountGeneration &&
          revision == _reminderRevision) {
        setState(() => _reminderSettings = value);
        widget.onHomeReminderChanged?.call(value);
      }
    } on Object {
      if (mounted &&
          generation == _accountGeneration &&
          revision == _reminderRevision)
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
      widget.onHomeReminderChanged?.call(value);
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
          widget.onHomeReminderChanged?.call(before);
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
    final next = observedReminderProgress(_reminderSettings, week, overview);
    if (next != null) unawaited(_saveReminderSettings(next));
  }

  void _openGradeNotice() {
    final notice = widget.gradeScoreNotice;
    if (notice == null) return;
    widget.onConsumeGradeNotice?.call();
    _openHomeNavigation(gradeNoticeTarget(notice));
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

  @override
  void dispose() {
    _campusLoader.dispose();
    _bhpanModalScope.value++;
    _bhpanModalScope.dispose();
    _visiblePage.dispose();
    _appBarSlot.dispose();
    _pageBusy.dispose();
    _tabPager.dispose();
    super.dispose();
  }

  int _agendaTodoRequest = 0;
  static const _tabs = UiDestination.values;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    const maxContentWidth = UbaaTheme.pageMaxWidth;
    if (_openedFeature case final feature?) _visitedFeatures.add(feature);
    final pages = _visitedFeatures.toList(growable: false);
    final body = IndexedStack(
      key: ValueKey<int>(_accountGeneration),
      index: _openedFeature == null ? 0 : pages.indexOf(_openedFeature!) + 1,
      children: <Widget>[
        TickerMode(enabled: _openedFeature == null, child: _buildTab(context)),
        for (final feature in pages)
          TickerMode(
            key: ValueKey<FeatureId>(feature),
            enabled: _openedFeature == feature,
            child: TooltipVisibility(
              visible: _openedFeature == feature,
              child: _buildFeaturePage(feature),
            ),
          ),
      ],
    );
    final touchRefresh = uiIsTouchPlatform(context);
    final refreshPage = _openedFeature != null
        ? () => _refreshFeature(_openedFeature!)
        : _utilityPage == null && _selectedIndex == 0
        ? _refreshHome
        : _onMeTab && widget.campusAccountService != null
        ? _refreshCampusAccount
        : null;
    // 宽屏侧栏直接列出“关于”，它与分类同级，不显示返回。
    final atRoot =
        _openedFeature == null &&
        (_utilityPage == null || (wide && _utilityPage == '关于'));
    final header = AppBar(
      centerTitle: false,
      toolbarHeight: wide ? 72 : 64,
      // 分类根页用大标题；进入功能、详情等下一级后标题小一号，层级更清楚，
      // 也给右上角的校区切换与更新状态留出空间。
      titleTextStyle: atRoot
          ? null
          : Theme.of(
              context,
            ).appBarTheme.titleTextStyle?.copyWith(fontSize: 20),
      automaticallyImplyLeading: false,
      // 下一级页面的标题紧跟返回箭头。
      titleSpacing: !atRoot
          ? 4
          : wide
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
      leading: !atRoot
          ? IconButton(
              tooltip: '返回',
              onPressed: _goBack,
              icon: const Icon(Icons.arrow_back),
            )
          : null,
      actions: <Widget>[
        if (widget.connectionStatus != null || widget.onCompleteLogin != null)
          UiConnectionStatusButton(
            status: widget.connectionStatus,
            onReconnect: widget.onReconnect,
            onCompleteLogin: widget.onCompleteLogin,
          ),
        if (_openedFeature case final feature?)
          ValueListenableBuilder<Map<FeatureId, Widget>>(
            valueListenable: _appBarSlot,
            builder: (context, slots, _) =>
                slots[feature] ?? const SizedBox.shrink(),
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
        _buildSyncStatus(touchRefresh ? null : refreshPage),
      ],
    );
    final shell = PopScope<void>(
      canPop: _openedFeature == null && _utilityPage == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        // 保持内容父层级与 key 稳定，宽窄切换不销毁已访问页面。
        body: UiAppBarSlot(
          slot: _appBarSlot,
          child: UiBusyScope(
            busy: _pageBusy,
            child: UiPlaceMemory(
              values: _places,
              onChanged: _savePlace,
              child: Row(
                children: <Widget>[
                  if (wide) _buildRail(context),

                  Expanded(
                    key: const ValueKey<String>('feature-pages'),
                    child: Column(
                      children: [
                        if (_selectedIndex != UiDestination.agenda.index ||
                            _openedFeature != null ||
                            _utilityPage != null)
                          Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: maxContentWidth,
                              ),
                              child: header,
                            ),
                          ),
                        Expanded(
                          child: ScrollGutters(
                            maxWidth: maxContentWidth,
                            child: SafeArea(
                              top: false,
                              bottom: wide,
                              child: UiPageTransition(
                                pageKey: (_openedFeature, _utilityPage),
                                deeper: !atRoot,
                                onBack:
                                    touchRefresh &&
                                        !atRoot &&
                                        widget.writeState.intent == null
                                    ? _goBack
                                    : null,
                                child: body,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : CompactNavigationBar(
                child: NavigationBar(
                  height:
                      56 +
                      (MediaQuery.textScalerOf(context).scale(12) - 12) * 3,
                  // 底栏放四个分类和“我的”；设置、关于与退出收在“我的”页。
                  selectedIndex: _selectedIndex < UiDestination.settings.index
                      ? _selectedIndex
                      : 0,
                  onDestinationSelected: _selectTab,
                  destinations: _tabs
                      .take(UiDestination.settings.index)
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
      onRefresh: () => _pull(() => _refreshFeature(feature)),
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
        onCgyyShowAll: () => setState(() => _cgyyOnlyAvailable = false),
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
        setState(() => _agendaTodoRequest++);
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
                setState(() => _openedFeature = feature);
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
      features: _tabs[index].features,
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

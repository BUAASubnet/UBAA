import 'dart:async';
import 'package:flutter/material.dart';
import 'search_field.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/write_callbacks.dart';
import '../shared/loading.dart' show LoadingPlaceholder;
import '../shared/refresh.dart' show RefreshViewport;
import '../app/home.dart' show uiCacheReadFailureText;
import 'details/detail_list.dart' show FeatureDetailList;
import 'error_card.dart' show FriendlyErrorCard;
import 'landing_menu.dart' show FeatureTabsBar;
import 'filters/feature_filters.dart'
    show FeatureFilterControls, FeatureFilterKind, uiFeatureFilterKind;
import '../theme.dart' show UbaaTheme;
import '../features/cgyy/lock_display.dart' show UbaaCgyyLockDisplayView;
import '../features/cgyy/reservation_flow.dart' show CgyyReservationFlow;
import '../features/coursework/coursework_overview.dart'
    show CourseworkOverview;
import '../features/coursework/assignment_filters.dart'
    show AssignmentListFilters;
import '../features/grades/flow.dart' show GradesFlow;
import '../features/libbook/reservation_flow.dart'
    show LibbookReservationFlow, LibbookReservationFlowState;
import '../features/schedule/content.dart' show ScheduleContent;
import '../features/schedule/flow.dart' show ScheduleFlow, ScheduleFlowState;
import '../features/ygdk/home_flow.dart' show YgdkHomeFlow;
import '../shared/feature_icons.dart' show uiFeatureIcon;
import '../write/cgyy/draft.dart' show CgyyFormContext, CgyyFormDraft;
import '../write/ygdk/draft.dart' show YgdkFormContext, YgdkFormDraft;
import 'state_panel.dart';

bool uiReadableCachedContent(FeatureSnapshot snapshot) =>
    {
      FeatureId.schedule,
      FeatureId.exam,
      FeatureId.grades,
      FeatureId.classroom,
      FeatureId.signin,
      FeatureId.spoc,
      FeatureId.ygdk,
      FeatureId.bykc,
      FeatureId.cgyy,
      FeatureId.libbook,
      FeatureId.evaluation,
    }.contains(snapshot.feature) &&
    snapshot.evidence?.origin == DataOrigin.persisted;

class FeatureDetailView extends StatefulWidget {
  const FeatureDetailView({
    required this.feature,
    this.isLanding = false,
    this.paginationGeneration = 0,
    this.loadingMore = false,
    this.moreError,
    this.hasMore = false,
    this.onLoadMore,
    this.onOpenLockDisplay,
    this.onReadLockDisplay,
    this.lockRefreshRevision = 0,
    this.visible = true,
    this.onLoadAllGrades,
    this.isBykcChosenDetail = false,
    this.bykcListCourse,
    this.bykcPendingCourseId,
    this.writeBusy = false,
    this.onOpenBykcChosen,
    required this.bykcFilters,
    required this.onBykcFiltersChanged,
    this.bykcFilterError,
    this.ygdkRecordsReadback,
    this.reminderSettings,
    this.reminderError,
    this.onReminderChanged,
    required this.snapshot,
    this.query,
    required this.onBack,
    required this.onRetry,
    this.onBykcWrite,
    this.onBykcSignWrite,
    this.onSigninWrite,
    this.onCgyyCancelWrite,
    this.onLibbookReserveWrite,
    this.onLibbookCancelWrite,
    this.onCgyySubmitWrite,
    this.onEvaluationWrite,
    this.onYgdkSubmitWrite,
    this.onPickYgdkPhoto,
    this.onCaptureYgdkPhoto,
    this.onQuery,
    this.onNavigate,
    this.onSwitchView,
    this.backLabel = '返回功能列表',
    this.onLoadAcademicTerms,
    this.onLoadExamTerms,
    this.onLoadAcademicWeeks,
    this.scheduleImports = const {},
    this.onSaveScheduleSemester,
    this.onCancelScheduleImport,
    this.onLoadCgyyPurposes,
    this.onLoadCgyyDefaults,
    this.cgyyOnlyAvailable = true,
    this.onCgyyShowAll,
    this.onSaveCgyyDefaults,
    this.onScheduleTitle,
    this.readCacheEpoch = 0,
    super.key,
  });

  final int paginationGeneration;
  final bool loadingMore, hasMore;
  final String? moreError;
  final Future<void> Function()? onLoadMore;
  final ValueChanged<String?>? onScheduleTitle;
  final bool isLanding, isBykcChosenDetail;
  final bool visible;
  final CgyyLockDisplayOpen? onOpenLockDisplay;
  final CgyyLockDisplayRead? onReadLockDisplay;
  final int lockRefreshRevision;
  final GradesAggregateLoader? onLoadAllGrades;
  final BykcCoursePresentation? bykcListCourse;
  final int? bykcPendingCourseId;

  /// 一点即完成的写入进行中，期间禁用其他写操作按钮。
  final bool writeBusy;
  final ValueChanged<FeatureDetail>? onOpenBykcChosen;
  final BykcCourseFilters bykcFilters;
  final ValueChanged<BykcCourseFilters> onBykcFiltersChanged;
  final String? bykcFilterError;
  final FeatureSnapshot? ygdkRecordsReadback;
  final YgdkReminderSettings? reminderSettings;
  final String? reminderError;
  final ValueChanged<bool>? onReminderChanged;
  final FeatureId feature;
  final FeatureSnapshot snapshot;
  final FeatureQuery? query;
  final VoidCallback onBack;
  final Future<void> Function() onRetry;
  final Future<void> Function(WriteOperation operation, int courseId)?
  onBykcWrite;
  final BykcSignStarter? onBykcSignWrite;
  final SigninStarter? onSigninWrite;
  final CgyyCancelStarter? onCgyyCancelWrite;
  final LibbookReserveStarter? onLibbookReserveWrite;
  final LibbookCancelStarter? onLibbookCancelWrite;
  final CgyyReservationStarter? onCgyySubmitWrite;
  final EvaluationSubmitStarter? onEvaluationWrite;
  final YgdkSubmitStarter? onYgdkSubmitWrite;
  final YgdkPhotoPicker? onPickYgdkPhoto;
  final YgdkPhotoPicker? onCaptureYgdkPhoto;
  final Future<void> Function(FeatureQuery query)? onQuery;
  final Future<void> Function(FeatureReadNavigation)? onNavigate;

  /// 同级页面分段切换；只有根层页面提供。
  final ValueChanged<FeatureQueryView>? onSwitchView;
  final String backLabel;
  final Future<FeatureResult> Function(bool forceRefresh)? onLoadAcademicTerms;
  final Future<FeatureResult> Function(bool forceRefresh)? onLoadExamTerms;
  final Future<FeatureResult> Function(String term, bool forceRefresh)?
  onLoadAcademicWeeks;
  final Map<String, ScheduleImportState> scheduleImports;
  final Future<void> Function(String)? onSaveScheduleSemester;
  final ValueChanged<String>? onCancelScheduleImport;
  final Future<FeatureResult> Function(bool forceRefresh)? onLoadCgyyPurposes;
  final Future<CgyyReservationDefaults?> Function()? onLoadCgyyDefaults;
  final bool cgyyOnlyAvailable;
  final VoidCallback? onCgyyShowAll;
  final Future<void> Function(CgyyReservationDefaults)? onSaveCgyyDefaults;
  final int readCacheEpoch;

  @override
  State<FeatureDetailView> createState() => FeatureDetailViewState();
}

class FeatureDetailViewState extends State<FeatureDetailView> {
  final _libraryKey = GlobalKey<LibbookReservationFlowState>();
  Future<void>? refreshLibrary() =>
      widget.onQuery == null ? null : _libraryKey.currentState?.refresh();

  final _cgyyDraft = CgyyFormDraft();
  final _ygdkDraft = YgdkFormDraft();
  final _scheduleKey = GlobalKey<ScheduleFlowState>();
  final _searchController = TextEditingController();
  bool _panelOpen = false;
  late AssignmentListFilters _assignmentFilters = AssignmentListFilters(
    isSpoc: widget.feature == FeatureId.spoc,
  );
  bool get _isAssignmentList =>
      (widget.feature == FeatureId.judge || widget.feature == FeatureId.spoc) &&
      (widget.query?.view ?? FeatureQueryView.summary) ==
          FeatureQueryView.summary;
  Set<BykcCourseStatus> get _bykcStatuses => widget.bykcFilters.statuses;
  Set<String> get _bykcCategories => widget.bykcFilters.categories;
  Set<String> get _bykcCampuses => widget.bykcFilters.campuses;

  void selectScheduleTerm() => _scheduleKey.currentState?.selectTerm();

  /// 筛选只调整当前列表；没有可调条件的页面不提供入口。
  void togglePanel() {
    if (_filterKind == null && !_panelOpen) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _panelOpen = !_panelOpen);
  }

  FeatureFilterKind? get _filterKind => widget.isLanding
      ? null
      : uiFeatureFilterKind(
          widget.feature,
          widget.query,
          assignmentList: _isAssignmentList,
          bykcChosenDetail: widget.isBykcChosenDetail,
        );

  /// 只有可浏览的结果列表提供搜索；菜单、详情、预约流程和课表沿各自入口操作。
  bool get _showsToolbar {
    if (widget.isLanding || _isLibraryReservation || _isCgyyReservation) {
      return false;
    }
    final view = widget.query?.view ?? FeatureQueryView.summary;
    return switch (widget.feature) {
      FeatureId.schedule => false,
      FeatureId.exam ||
      FeatureId.grades ||
      FeatureId.evaluation ||
      FeatureId.signin => _filterKind != null,
      FeatureId.bykc =>
        (view == FeatureQueryView.summary && !widget.isBykcChosenDetail) ||
            view == FeatureQueryView.bykcChosenCourses,
      FeatureId.spoc || FeatureId.judge =>
        _isAssignmentList || view == FeatureQueryView.judgeBatchDetails,
      FeatureId.classroom => view == FeatureQueryView.summary,
      FeatureId.libbook => view == FeatureQueryView.libbookBookings,
      FeatureId.cgyy => view == FeatureQueryView.cgyyOrders,
      // 阳光首页的搜索只筛选记录，由首页放在“打卡记录”标题下。
      FeatureId.ygdk => view == FeatureQueryView.ygdkRecords,
    };
  }

  /// 读取失败或功能本身没有条目时不提供搜索与筛选；条件导致的空结果保留入口。
  bool get _hasNothingToFilter {
    final snapshot = widget.snapshot;
    if (snapshot.details.isNotEmpty) return false;
    if (snapshot.status == FeatureLoadStatus.failure) return true;
    // 已确认空结果的刷新期间仍显示空状态，搜索栏不能来回出现。
    // 带概览的成功结果（如评教 0/0）同样没有可筛的条目；普通成功空列表
    // 可能来自分类等服务端条件，保留入口以便撤销。
    final empty =
        snapshot.status == FeatureLoadStatus.empty ||
        (snapshot.status == FeatureLoadStatus.success &&
            snapshot.overview != null) ||
        (snapshot.status == FeatureLoadStatus.loading &&
            snapshot.updatedAt != null);
    if (!empty) return false;
    final kind = _filterKind;
    final query = widget.query;
    return (kind == null || _filterControls(kind).activeCount == 0) &&
        query?.term == null &&
        _searchController.text.isEmpty;
  }

  String get _searchHint => switch (widget.feature) {
    FeatureId.exam => '搜索课程或考场',
    FeatureId.grades => '搜索课程名称',
    FeatureId.classroom => '搜索教学楼或教室',
    FeatureId.bykc => '搜索课程、教师或地点',
    FeatureId.spoc || FeatureId.judge => '搜索课程名称或作业标题',
    FeatureId.evaluation => '搜索课程或教师',
    FeatureId.signin => '搜索课程',
    FeatureId.libbook => '搜索场馆或座位',
    FeatureId.cgyy => '搜索研讨室或日期',
    FeatureId.ygdk => '搜索打卡记录',
    FeatureId.schedule => '搜索课程',
  };

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant FeatureDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.readCacheEpoch != widget.readCacheEpoch) {
      _cgyyDraft.clear();
      _ygdkDraft.clear();
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  @override
  void dispose() {
    _cgyyDraft.clear();
    _ygdkDraft.clear();
    _cgyyDraft.dispose();
    _ygdkDraft.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLanding &&
        widget.feature == FeatureId.cgyy &&
        widget.query?.view == FeatureQueryView.cgyyLockCode) {
      return UbaaCgyyLockDisplayView(
        open: widget.onOpenLockDisplay,
        read: widget.onReadLockDisplay,
        visible: widget.visible,
        refreshRevision: widget.lockRefreshRevision,
      );
    }
    final showDetails =
        (widget.snapshot.status == FeatureLoadStatus.success ||
                widget.snapshot.status == FeatureLoadStatus.stale ||
                widget.snapshot.status == FeatureLoadStatus.loading) &&
            widget.snapshot.details.isNotEmpty ||
        (_bykcEndReached && widget.snapshot.status == FeatureLoadStatus.empty);
    final defaultContent = Column(
      children: [
        if (widget.bykcFilterError case final message?
            when widget.feature == FeatureId.bykc)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(message),
            ),
          ),
        if (widget.snapshot.evidence?.cacheFailure case final failure?
            when widget.snapshot.status != FeatureLoadStatus.loading)
          if (uiCacheReadFailureText(failure) case final message?)
            Padding(padding: const EdgeInsets.all(12), child: Text(message)),
        if (widget.snapshot.status == FeatureLoadStatus.stale &&
            widget.snapshot.error != null)
          MaterialBanner(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(widget.snapshot.error!.message)],
            ),
            leading: const Icon(Icons.sync_problem),
            actions: [
              TextButton(
                onPressed: () => widget.onRetry(),
                child: const Text('重试'),
              ),
            ],
          ),
        if (widget.snapshot.overview case final overview?
            when overview is! GradesTermOverview &&
                overview is! ScheduleWeekOverview &&
                // 博雅已选的查询范围、SPOC 学期编码属于查询参数，不单独占卡片。
                overview is! BykcChosenOverview &&
                overview is! SpocTermOverview &&
                // 没有任何评教课程时只保留空状态，不显示 0/0 进度。
                !(overview is EvaluationProgressOverview &&
                    overview.totalCourses == 0) &&
                (widget.snapshot.status == FeatureLoadStatus.success ||
                    widget.snapshot.status == FeatureLoadStatus.empty ||
                    widget.snapshot.status == FeatureLoadStatus.stale ||
                    widget.snapshot.status == FeatureLoadStatus.loading))
          CourseworkOverview(
            overview: overview,
            complete: widget.snapshot.evidence?.complete ?? true,
          ),
        Expanded(
          key: const ValueKey<String>('stable-detail-list'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 同一列表始终保留State；明确空结果仍将details更新为空。
              ExcludeFocus(
                excluding: !showDetails,
                child: TickerMode(
                  enabled: showDetails,
                  child: Offstage(
                    offstage: !showDetails,
                    child: _details(context),
                  ),
                ),
              ),
              if (!showDetails)
                switch (widget.snapshot.status) {
                  FeatureLoadStatus.loading
                      when widget.snapshot.evidence?.complete != false &&
                          (uiReadableCachedContent(widget.snapshot) ||
                              widget.snapshot.updatedAt != null) =>
                    _empty(context),
                  FeatureLoadStatus.loading || FeatureLoadStatus.idle =>
                    const RefreshViewport(child: LoadingPlaceholder()),
                  FeatureLoadStatus.failure => _error(context),
                  _ => _empty(context),
                },
            ],
          ),
        ),
      ],
    );
    final content =
        !widget.isLanding &&
            widget.feature == FeatureId.libbook &&
            (widget.query?.view ?? FeatureQueryView.summary) !=
                FeatureQueryView.libbookBookings
        ? LibbookReservationFlow(
            key: _libraryKey,
            snapshot: widget.snapshot,
            query: widget.query ?? const FeatureQuery(),
            cacheEpoch: widget.readCacheEpoch,
            fallback: defaultContent,
            onReserve: widget.onLibbookReserveWrite,
            onQuery: widget.onQuery,
          )
        : !widget.isLanding &&
              widget.feature == FeatureId.cgyy &&
              {
                FeatureQueryView.summary,
                FeatureQueryView.cgyyDayInfo,
              }.contains(widget.query?.view ?? FeatureQueryView.summary)
        ? CgyyReservationFlow(
            snapshot: widget.snapshot,
            query: widget.query ?? const FeatureQuery(),
            cacheEpoch: widget.readCacheEpoch,
            fallback: defaultContent,
            onRetry: widget.onRetry,
            onSubmit: widget.onCgyySubmitWrite,
            formContext: _cgyyFormContext,
            onQuery: widget.onQuery,
            onlyAvailable: widget.cgyyOnlyAvailable,
            onShowAll: widget.onCgyyShowAll,
          )
        : widget.feature == FeatureId.ygdk &&
              (widget.query?.view ?? FeatureQueryView.summary) ==
                  FeatureQueryView.summary
        ? YgdkHomeFlow(
            formContext: _ygdkFormContext,
            snapshot: widget.snapshot,
            recordsReadback: widget.ygdkRecordsReadback,
            reminderSettings: widget.reminderSettings,
            reminderError: widget.reminderError,
            onReminderChanged: widget.onReminderChanged,
            query: widget.query ?? const FeatureQuery(),
            cacheEpoch: widget.readCacheEpoch,
            filter: _searchController.text,
            searchField: _searchField(context),
            fallback: defaultContent,
            onQuery: widget.onQuery,
            onSubmit: widget.onYgdkSubmitWrite,
            onPickPhoto: widget.onPickYgdkPhoto,
            onCapturePhoto: widget.onCaptureYgdkPhoto,
          )
        : !widget.isLanding && widget.feature == FeatureId.grades
        ? GradesFlow(
            snapshot: widget.snapshot,
            visible: widget.visible,
            cacheEpoch: widget.readCacheEpoch,
            filter: _searchController.text,
            fallback: defaultContent,
            loader: widget.onLoadAllGrades,
          )
        : widget.feature == FeatureId.schedule &&
              widget.onLoadAcademicWeeks != null
        ? ScheduleFlow(
            key: _scheduleKey,
            snapshot: widget.snapshot,
            query: widget.query,
            visible: widget.visible,
            epoch: widget.readCacheEpoch,
            loadWeeks: widget.onLoadAcademicWeeks!,
            loadTerms: widget.onLoadAcademicTerms,
            imports: widget.scheduleImports,
            onSave: widget.onSaveScheduleSemester,
            onCancelImport: widget.onCancelScheduleImport,
            onTitle: widget.onScheduleTitle,
            onQuery: widget.onQuery == null
                ? null
                : (query) {
                    return widget.onQuery!(query);
                  },
            child: defaultContent,
          )
        : defaultContent;
    final kind = _filterKind;
    final switchView = widget.onSwitchView;
    final showsToolbar = _showsToolbar && !_hasNothingToFilter;
    final body = showsToolbar || switchView != null
        ? Column(
            children: [
              if (switchView != null)
                FeatureTabsBar(
                  feature: widget.feature,
                  query: widget.query,
                  // 门锁密码叠在当前页之上打开，返回时回到原分段。
                  onSelect: (view) =>
                      view == FeatureQueryView.cgyyLockCode &&
                          widget.onNavigate != null
                      ? unawaited(
                          widget.onNavigate!(
                            FeatureReadNavigation(
                              feature: widget.feature,
                              query: const FeatureQuery(
                                view: FeatureQueryView.cgyyLockCode,
                              ),
                            ),
                          ),
                        )
                      : switchView(view),
                ),
              if (showsToolbar) _toolbar(context, kind),
              Expanded(child: content),
            ],
          )
        : content;
    // 筛选入口在工具栏里；工具栏隐藏时弹层也不再显示，已打开的弹层保留到用户关闭。
    if (kind == null || (!showsToolbar && !_panelOpen)) return body;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = MediaQuery.sizeOf(context).width >= 600;
        final colors = Theme.of(context).colorScheme;
        return Stack(
          children: [
            Positioned.fill(child: body),
            if (_panelOpen)
              Positioned.fill(
                // 宽屏是贴着按钮的弹层，不压暗页面；窄屏底部面板保留遮罩。
                child: ModalBarrier(
                  color: wide
                      ? Colors.transparent
                      : Theme.of(
                          context,
                        ).colorScheme.scrim.withValues(alpha: .26),
                  onDismiss: togglePanel,
                  semanticsLabel: '关闭筛选',
                ),
              ),
            Align(
              alignment: wide ? Alignment.topRight : Alignment.bottomCenter,
              child: ExcludeFocus(
                excluding: !_panelOpen,
                child: Offstage(
                  offstage: !_panelOpen,
                  child: Padding(
                    // 宽屏出现在工具栏下方，右边与页面内容对齐，不遮住筛选按钮。
                    padding: wide
                        ? EdgeInsets.only(
                            top: 60,
                            right: UbaaTheme.pageInsets(context).right,
                          )
                        : EdgeInsets.zero,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: wide ? 420 : constraints.maxWidth,
                        maxWidth: wide ? 420 : constraints.maxWidth,
                        maxHeight: constraints.maxHeight * .85,
                      ),
                      child: Material(
                        elevation: 8,
                        color: colors.surfaceContainerLow,
                        borderRadius: wide
                            ? BorderRadius.circular(16)
                            : const BorderRadius.vertical(
                                top: Radius.circular(20),
                              ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 标题与其他底部面板（UiSheetBody）同一字号与左边距。
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '筛选',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '关闭筛选',
                                    onPressed: togglePanel,
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ),
                            Flexible(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  0,
                                  24,
                                  16,
                                ),
                                child: _filterControls(kind),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _toolbar(BuildContext context, FeatureFilterKind? kind) {
    final count = kind == null ? 0 : _filterControls(kind).activeCount;
    return Padding(
      padding: UbaaTheme.pageInsets(context, top: 12, bottom: 4),
      child: Row(
        children: [
          Expanded(child: _searchField(context)),
          if (kind != null) ...[
            const SizedBox(width: 8),
            Badge(
              key: const ValueKey<String>('feature-filter-button'),
              isLabelVisible: count > 0,
              label: Text('$count'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              textColor: Theme.of(context).colorScheme.onPrimary,
              // 与搜索框同高，左右两侧的边缘对齐。
              child: count > 0
                  ? IconButton.filledTonal(
                      style: IconButton.styleFrom(
                        fixedSize: const Size.square(UiSearchField.height),
                      ),
                      tooltip: '筛选（$count 项生效）',
                      onPressed: togglePanel,
                      icon: const Icon(Icons.tune),
                    )
                  : IconButton.outlined(
                      style: IconButton.styleFrom(
                        fixedSize: const Size.square(UiSearchField.height),
                      ),
                      tooltip: '筛选',
                      onPressed: togglePanel,
                      icon: const Icon(Icons.tune),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context) => UiSearchField(
    fieldKey: const ValueKey<String>('feature-search-field'),
    controller: _searchController,
    hintText: _searchHint,
    onChanged: (_) => setState(() {}),
    onClear: _clearSearch,
  );

  bool get _isLibraryReservation =>
      !widget.isLanding &&
      widget.feature == FeatureId.libbook &&
      (widget.query?.view ?? FeatureQueryView.summary) !=
          FeatureQueryView.libbookBookings;

  bool get _isCgyyReservation =>
      widget.feature == FeatureId.cgyy &&
      {
        FeatureQueryView.summary,
        FeatureQueryView.cgyyDayInfo,
      }.contains(widget.query?.view ?? FeatureQueryView.summary);

  FeatureFilterControls _filterControls(FeatureFilterKind kind) =>
      FeatureFilterControls(
        kind: kind,
        feature: widget.feature,
        query: widget.query ?? const FeatureQuery(),
        details: widget.snapshot.details,
        onQuery: widget.onQuery,
        onLoadAcademicTerms: widget.onLoadExamTerms,
        readCacheEpoch: () => widget.readCacheEpoch,
        bykcFilters: widget.bykcFilters,
        onBykcFiltersChanged: widget.onBykcFiltersChanged,
        assignmentFilters: _isAssignmentList ? _assignmentFilters : null,
        onAssignmentFiltersChanged: (value) =>
            setState(() => _assignmentFilters = value),
        onLoadAssignmentHistory:
            widget.feature == FeatureId.spoc ||
                widget.query?.includeExpired == true ||
                widget.onQuery == null ||
                widget.snapshot.status == FeatureLoadStatus.loading
            ? null
            : () => widget.onQuery!(
                (widget.query ?? const FeatureQuery()).copyWith(
                  includeExpired: true,
                ),
              ),
      );

  YgdkFormContext get _ygdkFormContext =>
      YgdkFormContext(draft: _ygdkDraft, route: widget.snapshot.resolvedRoute);

  CgyyFormContext get _cgyyFormContext => CgyyFormContext(
    draft: _cgyyDraft,
    loadPurposes: widget.onLoadCgyyPurposes,
    loadDefaults: widget.onLoadCgyyDefaults,
    saveDefaults: widget.onSaveCgyyDefaults,
    route: widget.snapshot.resolvedRoute,
  );

  ScheduleWeekOverview? get _scheduleTimeline =>
      widget.snapshot.overview is ScheduleWeekOverview
      ? widget.snapshot.overview as ScheduleWeekOverview
      : null;

  bool get _bykcCatalog =>
      widget.feature == FeatureId.bykc &&
      (widget.query?.view ?? FeatureQueryView.summary) ==
          FeatureQueryView.summary;

  bool get _bykcEndReached {
    final snapshot = widget.snapshot;
    final page = snapshot.pagination;
    return _bykcCatalog &&
        !widget.loadingMore &&
        widget.moreError == null &&
        snapshot.error == null &&
        (snapshot.status == FeatureLoadStatus.success ||
            snapshot.status == FeatureLoadStatus.empty) &&
        snapshot.evidence?.origin != DataOrigin.persisted &&
        snapshot.evidence?.complete != false &&
        page != null &&
        (snapshot.status == FeatureLoadStatus.empty ||
            !(page.hasMore ?? (page.page < page.effectiveTotalPages)));
  }

  Widget _details(BuildContext context) {
    return FeatureDetailList(
      feature: widget.feature,
      // 后台续载下一页不影响已显示条目的操作；整页读取或刷新时才禁用。
      writesEnabled:
          (widget.snapshot.status != FeatureLoadStatus.loading ||
              widget.loadingMore) &&
          widget.bykcPendingCourseId == null &&
          !widget.writeBusy,
      details: _isAssignmentList
          ? _assignmentFilters.apply(
              widget.snapshot.details,
              _searchController.text,
            )
          : widget.snapshot.details,
      timeline: _scheduleTimeline,
      filter: _isAssignmentList || _isCgyyReservation
          ? ''
          : _searchController.text,
      bykcStatuses: _bykcStatuses,
      onBykcStatusesChanged: (statuses) => widget.onBykcFiltersChanged(
        widget.bykcFilters.copyWith(statuses: statuses),
      ),
      bykcCategories: _bykcCategories,
      bykcCampuses: _bykcCampuses,
      isBykcChosenDetail: widget.isBykcChosenDetail,
      bykcListCourse: widget.bykcListCourse,
      bykcPendingCourseId: widget.bykcPendingCourseId,
      onOpenBykcChosen: widget.onOpenBykcChosen,
      pagination: widget.snapshot.pagination,
      bykcEndReached: _bykcEndReached,
      paginationGeneration: widget.paginationGeneration,
      loadingMore: widget.loadingMore,
      moreError: widget.moreError,
      hasMore: widget.hasMore,
      onLoadMore: widget.onLoadMore,
      query: widget.query ?? const FeatureQuery(),
      onQuery: widget.onQuery == null
          ? null
          : (query) {
              return widget.onQuery!(query);
            },
      onNavigate: widget.onNavigate,
      onBykcWrite: widget.onBykcWrite,
      onBykcSignWrite: widget.onBykcSignWrite,
      onSigninWrite: widget.onSigninWrite,
      onCgyyCancelWrite: widget.onCgyyCancelWrite,
      onLibbookReserveWrite: widget.onLibbookReserveWrite,
      onLibbookCancelWrite: widget.onLibbookCancelWrite,
      onCgyySubmitWrite: widget.onCgyySubmitWrite,
      cgyyFormContext: _cgyyFormContext,
      ygdkFormContext: _ygdkFormContext,
      onEvaluationWrite: widget.onEvaluationWrite,
      onYgdkSubmitWrite: widget.onYgdkSubmitWrite,
      onPickYgdkPhoto: widget.onPickYgdkPhoto,
      onCaptureYgdkPhoto: widget.onCaptureYgdkPhoto,
    );
  }

  Widget _empty(BuildContext context) =>
      widget.feature == FeatureId.schedule &&
          (widget.snapshot.status == FeatureLoadStatus.empty ||
              (widget.snapshot.status == FeatureLoadStatus.loading &&
                  widget.snapshot.updatedAt != null)) &&
          (widget.query?.view == FeatureQueryView.scheduleWeek ||
              (widget.query?.view == FeatureQueryView.summary &&
                  widget.query?.term != null &&
                  widget.query?.week != null))
      ? ScheduleContent(details: const [], timeline: _scheduleTimeline)
      : RefreshViewport(
          child: UiStatePanel(
            icon: uiFeatureIcon(widget.feature),
            title: widget.isBykcChosenDetail
                ? '暂时无法显示这条选课记录'
                : widget.snapshot.evidence?.complete == false
                ? '暂时没有可显示的内容'
                : switch (widget.feature) {
                    FeatureId.signin => '今天没有需要签到的课程',
                    FeatureId.evaluation when _noEvaluationCourses =>
                      '当前没有评教任务',
                    _ => '暂无${widget.feature.title}数据',
                  },
            detail: switch (widget.snapshot.summary) {
              _ when _noEvaluationCourses => null,
              final summary? when summary.trim().isNotEmpty => summary,
              _ => null,
            },
          ),
        );

  /// 评教总数为 0（或未提供进度）时，空状态不再重复“已评 0/0 门”。
  bool get _noEvaluationCourses =>
      widget.feature == FeatureId.evaluation &&
      switch (widget.snapshot.overview) {
        EvaluationProgressOverview p => p.totalCourses == 0,
        _ => true,
      };

  Widget _error(BuildContext context) => RefreshViewport(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: FriendlyErrorCard(
            error:
                widget.snapshot.error ??
                const UiError(
                  code: UbaaErrorCode.internalError,
                  title: '读取失败',
                  message: '暂时无法加载该功能，请稍后重试。',
                  retryable: true,
                ),
            onRetry: () => widget.onRetry(),
          ),
        ),
      ),
    ),
  );
}

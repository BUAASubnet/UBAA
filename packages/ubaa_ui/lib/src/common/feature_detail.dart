import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/write_callbacks.dart';
import '../shared/loading.dart' show LoadingPlaceholder;
import '../shared/refresh.dart' show RefreshViewport;
import '../app/home.dart' show uiCacheReadFailureText;
import 'details/detail_list.dart' show FeatureDetailList;
import 'error_card.dart' show FriendlyErrorCard;
import 'landing_menu.dart' show FeatureLandingMenu;
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
    this.lockRefreshRevision = 0,
    this.visible = true,
    this.onLoadAllGrades,
    this.isBykcChosenDetail = false,
    this.bykcListCourse,
    this.bykcPendingCourseId,
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
    this.backLabel = '返回功能列表',
    this.onLoadAcademicTerms,
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
  final Future<CgyyLockDisplaySession> Function()? onOpenLockDisplay;
  final int lockRefreshRevision;
  final GradesAggregateLoader? onLoadAllGrades;
  final BykcCoursePresentation? bykcListCourse;
  final int? bykcPendingCourseId;
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
  final String backLabel;
  final Future<FeatureResult> Function(bool forceRefresh)? onLoadAcademicTerms;
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
      FeatureId.ygdk =>
        view == FeatureQueryView.summary ||
            view == FeatureQueryView.ygdkRecords,
    };
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
        visible: widget.visible,
        refreshRevision: widget.lockRefreshRevision,
      );
    }
    final showDetails =
        (widget.snapshot.status == FeatureLoadStatus.success ||
            widget.snapshot.status == FeatureLoadStatus.stale ||
            widget.snapshot.status == FeatureLoadStatus.loading) &&
        widget.snapshot.details.isNotEmpty;
    final defaultContent = widget.isLanding
        ? FeatureLandingMenu(
            feature: widget.feature,
            onOpen: widget.onNavigate!,
          )
        : Column(
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
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(uiCacheReadFailureText(failure)),
                ),
              if (widget.snapshot.status != FeatureLoadStatus.loading &&
                  widget.snapshot.evidence?.complete == false &&
                  widget.snapshot.details.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('当前内容尚不完整，连接后继续核对。'),
                ),
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
    final body = _showsToolbar
        ? Column(
            children: [
              _toolbar(context, kind),
              Expanded(child: content),
            ],
          )
        : content;
    if (kind == null) return body;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = MediaQuery.sizeOf(context).width >= 600;
        final colors = Theme.of(context).colorScheme;
        return Stack(
          children: [
            Positioned.fill(child: body),
            if (_panelOpen)
              Positioned.fill(
                child: ModalBarrier(
                  color: Colors.black26,
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
                    padding: wide ? const EdgeInsets.all(16) : EdgeInsets.zero,
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
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '筛选',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
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
                                  20,
                                  0,
                                  20,
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
          Expanded(
            child: TextField(
              key: const ValueKey<String>('feature-search-field'),
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: InputDecoration(
                isDense: true,
                hintText: _searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(UbaaTheme.controlRadius),
                ),
              ),
            ),
          ),
          if (kind != null) ...[
            const SizedBox(width: 8),
            Badge(
              key: const ValueKey<String>('feature-filter-button'),
              isLabelVisible: count > 0,
              label: Text('$count'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              textColor: Theme.of(context).colorScheme.onPrimary,
              child: count > 0
                  ? IconButton.filledTonal(
                      tooltip: '筛选（$count 项生效）',
                      onPressed: togglePanel,
                      icon: const Icon(Icons.tune),
                    )
                  : IconButton.outlined(
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
        onLoadAcademicTerms: widget.onLoadAcademicTerms,
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

  Widget _details(BuildContext context) {
    return FeatureDetailList(
      feature: widget.feature,
      writesEnabled:
          widget.snapshot.status != FeatureLoadStatus.loading &&
          widget.bykcPendingCourseId == null,
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
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    uiFeatureIcon(widget.feature),
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.snapshot.evidence?.complete == false
                        ? '当前数据尚不完整，连接后继续核对。'
                        : widget.isBykcChosenDetail
                        ? '当前无法显示此选课记录，请返回列表核对。'
                        : '暂无${widget.feature.title}数据',
                  ),
                  if (widget.snapshot.summary case final summary?
                      when summary.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(summary, textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        );

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
                  title: '加载失败',
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

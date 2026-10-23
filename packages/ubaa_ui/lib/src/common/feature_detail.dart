import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/write_callbacks.dart';
import '../shared/loading.dart' show LoadingPlaceholder;
import '../app/home.dart' show uiCacheReadFailureText;
import 'details/detail_list.dart' show FeatureDetailList;
import 'error_card.dart' show FriendlyErrorCard;
import 'landing_menu.dart' show FeatureLandingMenu;
import 'query/query_controls.dart'
    show FeatureQueryControls, FeatureQueryControlsState;
import '../features/cgyy/lock_display.dart' show UbaaCgyyLockDisplayView;
import '../features/cgyy/reservation_flow.dart'
    show CgyyReservationChoices, CgyyReservationFlow, CgyyReservationFlowState;
import '../features/coursework/coursework_overview.dart'
    show CourseworkOverview;
import '../features/coursework/assignment_filters.dart'
    show AssignmentListFilters, AssignmentFilterControls;
import '../features/grades/flow.dart' show GradesFlow;
import '../features/libbook/reservation_flow.dart'
    show
        LibbookReservationChoices,
        LibbookReservationFlow,
        LibbookReservationFlowState,
        LibbookReservationSchedule;
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
    this.onOpenLockDisplay,
    this.lockRefreshRevision = 0,
    this.visible = true,
    this.onLoadAllGrades,
    this.onGradeRoutes,
    this.isBykcChosenDetail = false,
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
    this.onFormRouteOptions,
    this.onScheduleTitle,
    this.readCacheEpoch = 0,
    super.key,
  });

  final ValueChanged<String?>? onScheduleTitle;
  final bool isLanding, isBykcChosenDetail;
  final bool visible;
  final Future<CgyyLockDisplaySession> Function()? onOpenLockDisplay;
  final int lockRefreshRevision;
  final GradesAggregateLoader? onLoadAllGrades;
  final ValueChanged<Map<String, ConnectionMode>>? onGradeRoutes;
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
  final Future<void> Function(Map<String, ConnectionMode>)? onFormRouteOptions;
  final int readCacheEpoch;

  @override
  State<FeatureDetailView> createState() => FeatureDetailViewState();
}

class FeatureDetailViewState extends State<FeatureDetailView> {
  final _libraryKey = GlobalKey<LibbookReservationFlowState>();
  final _libraryChoicesRevision = ValueNotifier(0);
  final _libraryQueryExpansion = ExpansibleController();
  final _cgyyKey = GlobalKey<CgyyReservationFlowState>();
  final _cgyyChoicesRevision = ValueNotifier(0);
  final _cgyyDraft = CgyyFormDraft();
  final _ygdkDraft = YgdkFormDraft();
  final _queryKey = GlobalKey<FeatureQueryControlsState>();
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

  void togglePanel() {
    if (widget.feature == FeatureId.schedule) {
      selectScheduleTerm();
      return;
    }
    if (!_panelOpen)
      _scheduleKey.currentState?.stopAutomatic(clearPrompt: false);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _panelOpen = !_panelOpen);
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
    _cgyyChoicesRevision.dispose();
    _libraryChoicesRevision.dispose();
    _libraryQueryExpansion.dispose();
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
                        FeatureLoadStatus.loading ||
                        FeatureLoadStatus.idle => const LoadingPlaceholder(),
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
            onChoicesChanged: () {
              if (mounted) _libraryChoicesRevision.value++;
            },
            snapshot: widget.snapshot,
            query: widget.query ?? const FeatureQuery(),
            cacheEpoch: widget.readCacheEpoch,
            filter: _searchController.text,
            fallback: defaultContent,
            onReserve: widget.onLibbookReserveWrite,
            onQuery: widget.onQuery == null
                ? null
                : (query) {
                    _queryKey.currentState?.adoptLibraryQuery(query);
                    return widget.onQuery!(query);
                  },
            onSeatQuery: (query) {
              _queryKey.currentState?.adoptLibraryQuery(query, clearDate: true);
              _libraryQueryExpansion.expand();
              setState(() => _panelOpen = true);
            },
            onDraftChanged: (query) => _queryKey.currentState
                ?.adoptLibraryQuery(query, clearDate: query.date == null),
          )
        : !widget.isLanding &&
              widget.feature == FeatureId.cgyy &&
              {
                FeatureQueryView.summary,
                FeatureQueryView.cgyyDayInfo,
              }.contains(widget.query?.view ?? FeatureQueryView.summary)
        ? CgyyReservationFlow(
            key: _cgyyKey,
            onChoicesChanged: () {
              if (mounted) _cgyyChoicesRevision.value++;
            },
            snapshot: widget.snapshot,
            query: widget.query ?? const FeatureQuery(),
            cacheEpoch: widget.readCacheEpoch,
            filter: _searchController.text,
            fallback: defaultContent,
            onRetry: widget.onRetry,
            onSubmit: widget.onCgyySubmitWrite,
            formContext: _cgyyFormContext,
            onQuery: widget.onQuery == null
                ? null
                : (query) {
                    _queryKey.currentState?.adoptCgyyQuery(query);
                    return widget.onQuery!(query);
                  },
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
            onRoutes: widget.onGradeRoutes,
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
                    _queryKey.currentState?.adoptScheduleQuery(query);
                    return widget.onQuery!(query);
                  },
            adoptDraft: (query) =>
                _queryKey.currentState?.adoptScheduleQuery(query),
            child: defaultContent,
          )
        : defaultContent;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = MediaQuery.sizeOf(context).width >= 600;
        return Stack(
          children: [
            Positioned.fill(child: content),
            if (_panelOpen)
              Positioned.fill(
                child: ModalBarrier(
                  color: Colors.black26,
                  onDismiss: togglePanel,
                  semanticsLabel: '关闭搜索与筛选',
                ),
              ),
            Align(
              alignment: wide ? Alignment.topRight : Alignment.bottomCenter,
              child: ExcludeFocus(
                excluding: !_panelOpen,
                child: Offstage(
                  offstage: !_panelOpen,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: wide ? 420 : constraints.maxWidth,
                      maxWidth: wide ? 420 : constraints.maxWidth,
                      maxHeight: constraints.maxHeight * .85,
                    ),
                    child: Material(
                      elevation: 8,
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            title: const Text('搜索与筛选'),
                            trailing: TextButton(
                              onPressed: togglePanel,
                              child: const Text('完成'),
                            ),
                          ),
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                children: [
                                  if (!widget.isLanding)
                                    TextField(
                                      controller: _searchController,
                                      decoration: InputDecoration(
                                        labelText: _isAssignmentList
                                            ? '课程名称或作业标题'
                                            : '筛选详情',
                                        prefixIcon: const Icon(Icons.search),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  if (_isAssignmentList)
                                    AssignmentFilterControls(
                                      filters: _assignmentFilters,
                                      onChanged: (value) => setState(
                                        () => _assignmentFilters = value,
                                      ),
                                      onLoadHistory:
                                          widget.feature == FeatureId.spoc ||
                                              widget.query?.includeExpired ==
                                                  true ||
                                              widget.onQuery == null ||
                                              widget.snapshot.status ==
                                                  FeatureLoadStatus.loading
                                          ? null
                                          : () => widget.onQuery!(
                                              (widget.query ??
                                                      const FeatureQuery())
                                                  .copyWith(
                                                    includeExpired: true,
                                                  ),
                                            ),
                                    ),
                                  if (widget.feature != FeatureId.judge &&
                                      widget.feature != FeatureId.spoc &&
                                      widget.onQuery != null &&
                                      _supportsQuery)
                                    if (_isCgyyReservation) ...[
                                      ValueListenableBuilder<int>(
                                        valueListenable: _cgyyChoicesRevision,
                                        builder: (context, _, _) =>
                                            _cgyyKey.currentState?.buildChoices(
                                              context,
                                            ) ??
                                            const SizedBox.shrink(),
                                      ),
                                      ExpansionTile(
                                        title: const Text('更多查询'),
                                        maintainState: true,
                                        children: [_queryControls()],
                                      ),
                                    ] else if (_isLibraryReservation) ...[
                                      ValueListenableBuilder<int>(
                                        valueListenable:
                                            _libraryChoicesRevision,
                                        builder: (context, _, _) =>
                                            _libraryKey.currentState
                                                ?.buildChoices(context) ??
                                            const SizedBox.shrink(),
                                      ),
                                      ExpansionTile(
                                        title: const Text('更多查询'),
                                        controller: _libraryQueryExpansion,
                                        maintainState: true,
                                        children: [_queryControls()],
                                      ),
                                    ] else
                                      _queryControls(),
                                ],
                              ),
                            ),
                          ),
                        ],
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

  bool get _isLibraryReservation =>
      !widget.isLanding &&
      widget.feature == FeatureId.libbook &&
      (widget.query?.view ?? FeatureQueryView.summary) !=
          FeatureQueryView.libbookBookings;

  bool get _isCgyyReservation =>
      !widget.isLanding &&
      widget.feature == FeatureId.cgyy &&
      {
        FeatureQueryView.summary,
        FeatureQueryView.cgyyDayInfo,
      }.contains(widget.query?.view ?? FeatureQueryView.summary);

  Widget _queryControls() => FeatureQueryControls(
    key: _queryKey,
    feature: widget.feature,
    details: widget.snapshot.details,
    snapshot: widget.snapshot,
    initialQuery: widget.query,
    onLoadAcademicTerms: widget.onLoadAcademicTerms,
    onLoadAcademicWeeks: widget.onLoadAcademicWeeks,
    readCacheEpoch: widget.readCacheEpoch,
    onApply: (query) {
      _scheduleKey.currentState?.stopAutomatic();
      _libraryKey.currentState?.adoptManualQuery(query);
      return widget.onQuery!(query);
    },
    bykcStatuses: _bykcStatuses,
    bykcCategories: _bykcCategories,
    bykcCampuses: _bykcCampuses,
    onBykcCategoriesChanged: (values) => widget.onBykcFiltersChanged(
      widget.bykcFilters.copyWith(categories: values),
    ),
    onBykcCampusesChanged: (values) => widget.onBykcFiltersChanged(
      widget.bykcFilters.copyWith(campuses: values),
    ),
    onBykcReset: () =>
        widget.onBykcFiltersChanged(const BykcCourseFilters.defaults()),
    onBykcStatusesChanged: (values) => widget.onBykcFiltersChanged(
      widget.bykcFilters.copyWith(statuses: values),
    ),
  );

  bool get _supportsQuery => switch (widget.feature) {
    FeatureId.schedule ||
    FeatureId.exam ||
    FeatureId.grades ||
    FeatureId.classroom ||
    FeatureId.bykc ||
    FeatureId.libbook ||
    FeatureId.ygdk ||
    FeatureId.cgyy ||
    FeatureId.signin ||
    FeatureId.spoc ||
    FeatureId.judge ||
    FeatureId.evaluation => true,
  };

  YgdkFormContext get _ygdkFormContext => YgdkFormContext(
    draft: _ygdkDraft,
    route: widget.snapshot.resolvedRoute,
    onRouteOptions: widget.onFormRouteOptions,
  );

  CgyyFormContext get _cgyyFormContext => CgyyFormContext(
    draft: _cgyyDraft,
    loadPurposes: widget.onLoadCgyyPurposes,
    route: widget.snapshot.resolvedRoute,
    onRouteOptions: widget.onFormRouteOptions,
  );

  ScheduleWeekOverview? get _scheduleTimeline =>
      widget.snapshot.overview is ScheduleWeekOverview
      ? widget.snapshot.overview as ScheduleWeekOverview
      : null;

  Widget _details(BuildContext context) {
    return FeatureDetailList(
      feature: widget.feature,
      writesEnabled: widget.snapshot.status != FeatureLoadStatus.loading,
      details: _isAssignmentList
          ? _assignmentFilters.apply(
              widget.snapshot.details,
              _searchController.text,
            )
          : widget.snapshot.details,
      timeline: _scheduleTimeline,
      filter: _isAssignmentList ? '' : _searchController.text,
      bykcStatuses: _bykcStatuses,
      onBykcStatusesChanged: (statuses) => widget.onBykcFiltersChanged(
        widget.bykcFilters.copyWith(statuses: statuses),
      ),
      onOpenFilterPanel: togglePanel,
      bykcCategories: _bykcCategories,
      bykcCampuses: _bykcCampuses,
      isBykcChosenDetail: widget.isBykcChosenDetail,
      onOpenBykcChosen: widget.onOpenBykcChosen,
      pagination: widget.snapshot.pagination,
      query: widget.query ?? const FeatureQuery(),
      onQuery: widget.onQuery == null
          ? null
          : (query) {
              if (widget.feature == FeatureId.classroom) {
                _queryKey.currentState?.adoptClassroomQuery(query);
              }
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
      : Center(
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
        );

  Widget _error(BuildContext context) => Center(
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
  );
}

part of '../widgets.dart';

/// 详情列表的本地筛选只作用于 bridge 白名单字段。
class _FeatureDetailList extends StatefulWidget {
  const _FeatureDetailList({
    required this.feature,
    required this.details,
    this.filter = '',
    this.bykcStatuses = _defaultBykcStatuses,
    this.isBykcChosenDetail = false,
    this.onOpenBykcChosen,
    this.pagination,
    this.query,
    this.onQuery,
    this.onNavigate,
    this.onBykcWrite,
    this.onBykcSignWrite,
    this.onSigninWrite,
    this.onCgyyCancelWrite,
    this.onLibbookReserveWrite,
    this.onLibbookCancelWrite,
    this.onCgyySubmitWrite,
    this.cgyyFormContext,
    this.onEvaluationWrite,
    this.onYgdkSubmitWrite,
    this.onPickYgdkPhoto,
  });

  final String filter;
  final Set<BykcCourseStatus> bykcStatuses;
  final bool isBykcChosenDetail;
  final ValueChanged<FeatureDetail>? onOpenBykcChosen;
  final FeatureId feature;
  final List<FeatureDetail> details;
  final FeaturePagination? pagination;
  final FeatureQuery? query;
  final Future<void> Function(FeatureQuery query)? onQuery;
  final Future<void> Function(FeatureReadNavigation)? onNavigate;
  final Future<void> Function(WriteOperation operation, int courseId)?
  onBykcWrite;
  final BykcSignStarter? onBykcSignWrite;
  final SigninStarter? onSigninWrite;
  final CgyyCancelStarter? onCgyyCancelWrite;
  final LibbookReserveStarter? onLibbookReserveWrite;
  final LibbookCancelStarter? onLibbookCancelWrite;
  final CgyyReservationStarter? onCgyySubmitWrite;
  final _CgyyFormContext? cgyyFormContext;
  final EvaluationSubmitStarter? onEvaluationWrite;
  final YgdkSubmitStarter? onYgdkSubmitWrite;
  final YgdkPhotoPicker? onPickYgdkPhoto;

  @override
  State<_FeatureDetailList> createState() => _FeatureDetailListState();
}

class _FeatureDetailListState extends State<_FeatureDetailList> {
  static const _pageSize = 20;
  final Set<String> _selectedEvaluationKeys = <String>{};
  final List<(String, String)> _selectedJudgeKeys = [];
  int _page = 0;

  @override
  void didUpdateWidget(covariant _FeatureDetailList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter ||
        oldWidget.bykcStatuses != widget.bykcStatuses)
      _page = 0;
    final validKeys = <String>{
      for (final detail in widget.details)
        if (_evaluationSubmitTarget(detail) case final target?)
          target.selectionKey,
    };
    _selectedEvaluationKeys.removeWhere((key) => !validKeys.contains(key));
    final judgeKeys = {
      for (final detail in widget.details)
        if (detail.presentation case JudgeAssignmentPresentation p
            when !p.isDetail)
          (p.courseId, p.assignmentId),
    };
    _selectedJudgeKeys.removeWhere((key) => !judgeKeys.contains(key));
  }

  @override
  Widget build(BuildContext context) {
    // 列表的构建委托可能保留子元素；外层显式依赖主题，切换时更新标题样式。
    final theme = Theme.of(context);
    final isBykcStatistics = _isBykcStatistics(widget.feature, widget.details);
    final unpagedLocal =
        widget.feature == FeatureId.exam ||
        widget.feature == FeatureId.classroom ||
        (widget.feature == FeatureId.schedule &&
            widget.details.every(
              (d) => d.presentation is ScheduleCoursePresentation,
            )) ||
        isBykcStatistics ||
        (widget.feature == FeatureId.bykc &&
            widget.details.isNotEmpty &&
            widget.details.every(
              (d) => d.presentation is BykcChosenPresentation,
            ));
    final query = widget.filter.trim().toLowerCase();
    final candidates = widget.feature != FeatureId.bykc
        ? widget.details
        : widget.details
              .where(
                (detail) =>
                    detail.presentation is! BykcCoursePresentation ||
                    (detail.presentation! as BykcCoursePresentation).isDetail ||
                    _matchesBykcStatuses(
                      detail.presentation! as BykcCoursePresentation,
                      widget.bykcStatuses,
                    ),
              )
              .toList();
    final details = query.isEmpty
        ? candidates
        : candidates
              .where((detail) {
                final values = <String>[
                  detail.title,
                  ..._assignmentSearchValues(detail.presentation),
                  ..._academicSearchValues(detail.presentation),
                  ..._bykcSearchValues(detail.presentation),
                  if (detail.presentation case YgdkRecordPresentation record)
                    ..._ygdkRecordSearchValues(record),
                  if (detail.subtitle case final subtitle?) subtitle,
                  for (final field in detail.fields) ...<String>[
                    field.label,
                    field.value,
                  ],
                ];
                return values.any(
                  (value) => value.toLowerCase().contains(query),
                );
              })
              .toList(growable: false);
    final serverPagination = widget.pagination;
    final pageCount = serverPagination == null && !unpagedLocal
        ? details.isEmpty
              ? 0
              : (details.length + _pageSize - 1) ~/ _pageSize
        : 1;
    final page = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
    final start = page * _pageSize;
    final visible = serverPagination == null && !unpagedLocal
        ? details.skip(start).take(_pageSize).toList(growable: false)
        : details;
    final pendingEvaluationsByKey = <String, EvaluationSubmitTarget>{};
    for (final detail in widget.details) {
      if (_evaluationSubmitTarget(detail) case final target?) {
        pendingEvaluationsByKey.putIfAbsent(target.selectionKey, () => target);
      }
    }
    final pendingEvaluations = pendingEvaluationsByKey.values.toList(
      growable: false,
    );
    final selectedEvaluations = pendingEvaluations
        .where(
          (target) => _selectedEvaluationKeys.contains(target.selectionKey),
        )
        .toList(growable: false);
    return Column(
      children: <Widget>[
        ..._judgeBatchFields(setState),
        ..._evaluationBatchFields(
          setState,
          pendingEvaluations,
          selectedEvaluations,
        ),
        Expanded(
          // 翻页创建新的内容滚动位置；搜索与批量选择仍由外层 State 保留。
          // 同页刷新、父子返回不改变 key，继续保留本页滚动状态。
          child: KeyedSubtree(
            key: ValueKey((page, serverPagination?.page)),
            child: isBykcStatistics
                ? _BykcStatisticsContent(
                    total: widget.details
                        .map((d) => d.presentation)
                        .whereType<BykcStatisticsPresentation>()
                        .single,
                    details: details,
                  )
                : details.isEmpty
                ? Center(
                    child: Text(
                      widget.feature == FeatureId.bykc &&
                              widget.query?.view == FeatureQueryView.summary
                          ? '当前筛选条件下暂无课程'
                          : '没有匹配的详情',
                    ),
                  )
                : _supportsParticipationContent(widget.feature, visible)
                ? _CourseParticipationContent(
                    feature: widget.feature,
                    details: visible,
                    onSignin: widget.onSigninWrite,
                    evaluationRow: (detail) =>
                        _evaluationCourseRow(detail, setState),
                  )
                : _supportsAssignmentContent(widget.feature, visible)
                ? _AssignmentContent(
                    details: visible,
                    selection: (detail) => _judgeSelection(detail, setState),
                    onNavigate: widget.onNavigate,
                  )
                : _supportsAcademicContent(widget.feature, visible)
                ? _AcademicResultContent(
                    feature: widget.feature,
                    details: visible,
                    onNavigate: widget.onNavigate,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final detail = visible[index];
                      if (_supportsAssignmentContent(widget.feature, [
                        detail,
                      ])) {
                        return LayoutBuilder(
                          builder: (context, constraints) => _AssignmentCard(
                            detail: detail,
                            wide: constraints.maxWidth >= 708,
                            selection: _judgeSelection(detail, setState),
                            onNavigate: widget.onNavigate,
                          ),
                        );
                      }
                      if (widget.feature == FeatureId.ygdk) {
                        if (detail.presentation
                            case YgdkRecordPresentation record) {
                          return _YgdkRecordCard(record);
                        }
                      }
                      if (widget.feature == FeatureId.bykc) {
                        if (detail.presentation
                            case BykcCoursePresentation course) {
                          if (course.isDetail)
                            return _bykcCourseDetails(context, detail, course);
                          return _BykcCourseCard(
                            course: course,
                            onTap:
                                detail.readNavigation == null ||
                                    widget.onNavigate == null
                                ? null
                                : () => widget.onNavigate!(
                                    detail.readNavigation!,
                                  ),
                          );
                        }
                        if (detail.presentation
                            case BykcChosenPresentation course) {
                          if (widget.isBykcChosenDetail)
                            return _bykcChosenDetails(context, detail, course);
                          return _BykcChosenCard(
                            course: course,
                            onTap: widget.onOpenBykcChosen == null
                                ? null
                                : () => widget.onOpenBykcChosen!(detail),
                          );
                        }
                      }
                      final courseId = _courseId(detail);
                      final bykcSelectAction = detail
                          .action<BykcSelectAction>();
                      final bykcDeselectAction = detail
                          .action<BykcDeselectAction>();
                      final bykcSignInAction = _bykcSignAction(
                        detail,
                        BykcSignKind.signIn,
                      );
                      final bykcSignOutAction = _bykcSignAction(
                        detail,
                        BykcSignKind.signOut,
                      );
                      final signinAction = detail.action<SigninPerformAction>();
                      final cgyyCancelAction = _cgyyCancelAction(detail);
                      final libbookReserveAction = detail
                          .action<LibbookReserveAction>();
                      final libbookCancelAction = detail
                          .action<LibbookCancelAction>();
                      final cgyyReservation = _cgyyReserveAction(detail);
                      final evaluation = _evaluationSubmitTarget(detail);
                      final ygdkAction = _ygdkAction(detail);
                      final canBykcSign =
                          bykcSignInAction?.eligibility ==
                          ActionEligibility.allowed;
                      final canBykcSignOut =
                          bykcSignOutAction?.eligibility ==
                          ActionEligibility.allowed;
                      final canBykcSelect =
                          bykcSelectAction?.eligibility ==
                          ActionEligibility.allowed;
                      final canBykcDeselect =
                          bykcDeselectAction?.eligibility ==
                          ActionEligibility.allowed;
                      final canSignin =
                          signinAction?.eligibility ==
                              ActionEligibility.allowed &&
                          signinAction!.scheduleId.trim().isNotEmpty;
                      final canLibbookReserve =
                          libbookReserveAction?.eligibility ==
                              ActionEligibility.allowed &&
                          <String>[
                            libbookReserveAction!.areaId,
                            libbookReserveAction.seatId,
                            libbookReserveAction.day,
                            libbookReserveAction.segment,
                            libbookReserveAction.startTime,
                            libbookReserveAction.endTime,
                          ].every((value) => value.trim().isNotEmpty);
                      final canLibbookCancel =
                          libbookCancelAction?.eligibility ==
                              ActionEligibility.allowed &&
                          libbookCancelAction!.bookingId.trim().isNotEmpty &&
                          libbookCancelAction.page > 0 &&
                          libbookCancelAction.limit > 0;
                      if (widget.feature == FeatureId.libbook &&
                          detail.presentation is LibbookBookingPresentation) {
                        return _libbookBookingRow(
                          context,
                          detail,
                          detail.presentation! as LibbookBookingPresentation,
                          libbookCancelAction,
                          canLibbookCancel,
                        );
                      }
                      if (widget.feature == FeatureId.cgyy &&
                          detail.presentation is CgyyOrderPresentation) {
                        return _cgyyOrderRow(
                          context,
                          detail,
                          detail.presentation! as CgyyOrderPresentation,
                          cgyyCancelAction,
                        );
                      }
                      if (detail.presentation case CgyyLockPresentation lock
                          when widget.feature == FeatureId.cgyy) {
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_outline),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    lock.available ? '当前有可用门锁信息' : '当前无可用门锁信息',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                detail.title,
                                style: theme.textTheme.titleMedium,
                              ),
                              if (detail.subtitle case final subtitle?
                                  when subtitle.trim().isNotEmpty) ...<Widget>[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                              for (final field in detail.fields) ...<Widget>[
                                const SizedBox(height: 8),
                                _DetailField(
                                  label: field.label,
                                  value: field.value,
                                ),
                              ],
                              ..._evaluationSelectionFields(
                                setState,
                                evaluation,
                              ),
                              ..._bykcCourseWriteFields(
                                context,
                                courseId,
                                bykcSelectAction,
                                bykcDeselectAction,
                                canBykcSelect,
                                canBykcDeselect,
                              ),
                              ..._bykcSignWriteFields(
                                context,
                                bykcSignInAction,
                                bykcSignOutAction,
                                canBykcSign,
                                canBykcSignOut,
                              ),
                              ..._signinWriteFields(
                                context,
                                signinAction,
                                canSignin,
                              ),
                              ..._libbookCancelWriteFields(
                                context,
                                libbookCancelAction,
                                canLibbookCancel,
                              ),
                              ..._cgyyCancelWriteFields(cgyyCancelAction),
                              ..._libbookReserveWriteFields(
                                context,
                                libbookReserveAction,
                                canLibbookReserve,
                              ),
                              ..._evaluationSubmitFields(evaluation),
                              ..._cgyyReserveWriteFields(
                                context,
                                cgyyReservation,
                              ),
                              ..._ygdkWriteFields(context, ygdkAction, detail),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
        ..._paginationFields(setState, serverPagination, pageCount, page),
      ],
    );
  }
}

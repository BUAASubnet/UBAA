import '../../shared/refresh.dart' show RefreshViewport;
import 'package:ubaa_ui/src/theme.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show setEquals;
import '../../shared/infinite_scroll.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/write_callbacks.dart';
import '../detail_fields.dart' show DetailField;
import '../../features/academic/content.dart'
    show AcademicResultContent, uiSupportsAcademicContent;
import '../../features/bykc/chosen_card.dart' show BykcChosenCard;
import '../../features/bykc/course_card.dart' show BykcCourseCard;
import '../../features/bykc/display.dart'
    show
        BykcInfoLine,
        BykcStatusChip,
        uiBykcCheckinLabel,
        uiBykcDate,
        uiBykcDisplayStatus,
        uiBykcPassLabel,
        uiBykcRange,
        uiBykcSearchValues,
        uiDefaultBykcStatuses,
        uiMatchesBykcFilters;
import '../../features/bykc/section.dart' show BykcSection;
import '../../features/bykc/statistics.dart'
    show BykcStatisticsContent, uiIsBykcStatistics;
import '../../features/bykc/supplement.dart'
    show uiBykcContactFields, uiBykcDisplaySignFields, uiBykcSupplementSections;
import '../../features/coursework/assignment_content.dart'
    show
        AssignmentCard,
        AssignmentContent,
        uiAssignmentSearchValues,
        uiSupportsAssignmentContent;
import '../../features/coursework/course_participation.dart'
    show CourseParticipationContent, uiSupportsParticipationContent;
import '../../features/exam/timeline.dart' show uiAcademicSearchValues;
import '../../features/schedule/content.dart' show ScheduleContent;
import '../../features/ygdk/record_card.dart'
    show YgdkRecordCard, uiYgdkRecordSearchValues;
import '../../shared/text.dart' show uiNonBlank, uiHiddenAcademicField;
import '../../write/cgyy/draft.dart' show CgyyFormContext;
import '../../write/cgyy/form.dart'
    show uiCgyyActionKey, uiCollectCgyyReservation;
import '../../write/ygdk/draft.dart' show YgdkFormContext;
import '../../write/ygdk/form.dart' show uiCollectYgdkForm;

part 'assignments.dart';
part 'evaluation_row.dart';
part 'bykc_actions.dart';
part 'bykc_details.dart';
part 'cgyy_actions.dart';
part 'order_row.dart';
part 'evaluation_actions.dart';
part 'libbook_actions.dart';
part 'booking_row.dart';
part 'ygdk_actions.dart';
part 'cgyy_form.dart';
part 'ygdk_form.dart';

/// 详情列表的本地筛选只作用于 bridge 白名单字段。
class FeatureDetailList extends StatefulWidget {
  const FeatureDetailList({
    required this.feature,
    required this.details,
    this.writesEnabled = true,
    this.timeline,
    this.filter = '',
    this.bykcStatuses = uiDefaultBykcStatuses,
    this.onBykcStatusesChanged,
    this.bykcCategories = const {},
    this.bykcCampuses = const {},
    this.isBykcChosenDetail = false,
    this.bykcListCourse,
    this.bykcPendingCourseId,
    this.onOpenBykcChosen,
    this.pagination,
    this.paginationGeneration = 0,
    this.loadingMore = false,
    this.moreError,
    this.hasMore = false,
    this.onLoadMore,
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
    this.ygdkFormContext,
    this.onEvaluationWrite,
    this.onYgdkSubmitWrite,
    this.onPickYgdkPhoto,
    this.onCaptureYgdkPhoto,
  });

  final String filter;
  final Set<BykcCourseStatus> bykcStatuses;
  final ValueChanged<Set<BykcCourseStatus>>? onBykcStatusesChanged;
  final Set<String> bykcCategories, bykcCampuses;
  final bool isBykcChosenDetail;
  final BykcCoursePresentation? bykcListCourse;
  final int? bykcPendingCourseId;
  final ValueChanged<FeatureDetail>? onOpenBykcChosen;
  final FeatureId feature;
  // 刷新中保留按钮及列表布局，只暂停旧结果携带的写入动作。
  final bool writesEnabled;
  final List<FeatureDetail> details;
  final ScheduleWeekOverview? timeline;
  final FeaturePagination? pagination;
  final int paginationGeneration;
  final bool loadingMore, hasMore;
  final String? moreError;
  final Future<void> Function()? onLoadMore;
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
  final CgyyFormContext? cgyyFormContext;
  final YgdkFormContext? ygdkFormContext;
  final EvaluationSubmitStarter? onEvaluationWrite;
  final YgdkSubmitStarter? onYgdkSubmitWrite;
  final YgdkPhotoPicker? onPickYgdkPhoto;
  final YgdkPhotoPicker? onCaptureYgdkPhoto;

  @override
  State<FeatureDetailList> createState() => _FeatureDetailListState();
}

class _FeatureDetailListState extends State<FeatureDetailList> {
  int _filterGeneration = 0;
  final Set<String> _selectedEvaluationKeys = <String>{};

  @override
  void didUpdateWidget(covariant FeatureDetailList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter ||
        !setEquals(oldWidget.bykcStatuses, widget.bykcStatuses) ||
        !setEquals(oldWidget.bykcCategories, widget.bykcCategories) ||
        !setEquals(oldWidget.bykcCampuses, widget.bykcCampuses)) {
      _filterGeneration++;
    }
    final validKeys = <String>{
      for (final detail in widget.details)
        if (_evaluationSubmitTarget(detail) case final target?)
          target.selectionKey,
    };
    _selectedEvaluationKeys.removeWhere((key) => !validKeys.contains(key));
  }

  @override
  Widget build(BuildContext context) {
    // 列表的构建委托可能保留子元素；外层显式依赖主题，切换时更新标题样式。
    final theme = Theme.of(context);
    final isBykcStatistics = uiIsBykcStatistics(widget.feature, widget.details);
    final query = widget.filter.trim().toLowerCase();
    final candidates = widget.feature != FeatureId.bykc
        ? widget.details
        : widget.details
              .where(
                (detail) =>
                    detail.presentation is! BykcCoursePresentation ||
                    (detail.presentation! as BykcCoursePresentation).isDetail ||
                    uiMatchesBykcFilters(
                      detail.presentation! as BykcCoursePresentation,
                      widget.bykcStatuses,
                      widget.bykcCategories,
                      widget.bykcCampuses,
                    ),
              )
              .toList();
    final details = query.isEmpty
        ? candidates
        : candidates
              .where((detail) {
                final values = <String>[
                  detail.title,
                  ...uiAssignmentSearchValues(detail.presentation),
                  ...uiAcademicSearchValues(detail.presentation),
                  ...uiBykcSearchValues(detail.presentation),
                  if (detail.presentation case YgdkRecordPresentation record)
                    ...uiYgdkRecordSearchValues(record),
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
    final visible = details;
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
        Expanded(
          child: InfiniteScroll(
            onLoadMore: widget.onLoadMore,
            loading: widget.loadingMore,
            error: widget.moreError,
            hasMore: widget.hasMore,
            child: KeyedSubtree(
              key: ValueKey((widget.paginationGeneration, _filterGeneration)),
              child: isBykcStatistics
                  ? BykcStatisticsContent(
                      total: widget.details
                          .map((d) => d.presentation)
                          .whereType<BykcStatisticsPresentation>()
                          .single,
                      details: details,
                    )
                  : details.isEmpty &&
                        widget.feature == FeatureId.schedule &&
                        widget.details.isNotEmpty &&
                        widget.details.every(
                          (d) => d.presentation is ScheduleCoursePresentation,
                        )
                  ? ScheduleContent(
                      details: const [],
                      timeline: widget.timeline,
                      timeSource: widget.details,
                      emptyMessage: '没有匹配的课程',
                    )
                  : details.isEmpty
                  ? RefreshViewport(
                      child: Center(
                        child: Text(
                          widget.feature == FeatureId.bykc &&
                                  widget.query?.view == FeatureQueryView.summary
                              ? '已加载内容中没有匹配项'
                              : widget.feature == FeatureId.judge
                              ? '暂无符合条件的希冀作业'
                              : widget.feature == FeatureId.spoc
                              ? '暂无符合条件的 SPOC 作业'
                              : '没有匹配的详情',
                        ),
                      ),
                    )
                  : uiSupportsParticipationContent(widget.feature, visible)
                  ? CourseParticipationContent(
                      feature: widget.feature,
                      details: visible,
                      onSignin: widget.onSigninWrite,
                      writesEnabled: widget.writesEnabled,
                      evaluationRow: (detail) =>
                          _evaluationCourseRow(detail, setState),
                    )
                  : uiSupportsAssignmentContent(widget.feature, visible)
                  ? AssignmentContent(
                      details: visible,
                      onNavigate: widget.onNavigate,
                    )
                  : uiSupportsAcademicContent(widget.feature, visible)
                  ? AcademicResultContent(
                      feature: widget.feature,
                      details: visible,
                      timeline: widget.timeline,
                      query: widget.query,
                      onQuery: widget.onQuery,
                      onNavigate: widget.onNavigate,
                    )
                  : ListView.separated(
                      padding: UbaaTheme.pageInsets(context),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final detail = visible[index];
                        if (uiSupportsAssignmentContent(widget.feature, [
                          detail,
                        ])) {
                          return LayoutBuilder(
                            builder: (context, constraints) => AssignmentCard(
                              detail: detail,
                              wide: constraints.maxWidth >= 708,
                              onNavigate: widget.onNavigate,
                            ),
                          );
                        }
                        if (widget.feature == FeatureId.ygdk) {
                          if (detail.presentation
                              case YgdkRecordPresentation record) {
                            return YgdkRecordCard(record);
                          }
                        }
                        if (widget.feature == FeatureId.bykc) {
                          if (detail.presentation
                              case BykcCoursePresentation course) {
                            if (course.isDetail)
                              return _bykcCourseDetails(
                                context,
                                detail,
                                course,
                              );
                            return BykcCourseCard(
                              course: course,
                              action: _bykcListAction(
                                detail,
                                course.id,
                                selected: course.selected == true,
                                full:
                                    uiBykcDisplayStatus(course) ==
                                    BykcCourseStatus.full,
                              ),
                              onTap:
                                  widget.bykcPendingCourseId != null ||
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
                              return _bykcChosenDetails(
                                context,
                                detail,
                                course,
                              );
                            return BykcChosenCard(
                              course: course,
                              action: _bykcListAction(
                                detail,
                                course.courseId,
                                selected: true,
                              ),
                              onTap:
                                  widget.bykcPendingCourseId != null ||
                                      widget.onOpenBykcChosen == null
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
                        final signinAction = detail
                            .action<SigninPerformAction>();
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
                                      lock.available
                                          ? '当前有可用门锁信息'
                                          : '当前无可用门锁信息',
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
                                    when subtitle
                                        .trim()
                                        .isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                                for (final field in detail.fields.where(
                                  (f) => !uiHiddenAcademicField(f.label),
                                )) ...<Widget>[
                                  const SizedBox(height: 8),
                                  DetailField(
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
                                ..._ygdkWriteFields(
                                  context,
                                  ygdkAction,
                                  detail,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
        // 选择评教课程后在底部操作，避免批量栏插在列表中间跳动。
        ..._evaluationBatchFields(
          setState,
          pendingEvaluations,
          selectedEvaluations,
        ),
      ],
    );
  }
}

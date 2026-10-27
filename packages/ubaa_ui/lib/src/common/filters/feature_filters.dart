import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/feedback.dart';
import '../../features/academic/terms.dart' show AcademicTermDialog;
import '../../features/bykc/display.dart'
    show uiBykcCampusOptions, uiBykcStatusLabel, uiDefaultBykcStatuses;
import '../../features/coursework/assignment_filters.dart'
    show AssignmentFilterControls, AssignmentListFilters;

/// 列表可调的用户条件；视图切换和协议参数由页面导航负责，不进入筛选。
enum FeatureFilterKind { status, bykc, assignments }

/// 服务端已提供的派生视图，以名称展示，点选后立即重新读取。
const _statusViews = <FeatureId, List<(FeatureQueryView, String)>>{
  FeatureId.exam: [
    (FeatureQueryView.summary, '全部'),
    (FeatureQueryView.examArranged, '已安排'),
    (FeatureQueryView.examNotArranged, '未安排'),
  ],
  FeatureId.grades: [
    (FeatureQueryView.summary, '全部'),
    (FeatureQueryView.gradesScored, '已出成绩'),
    (FeatureQueryView.gradesMissing, '待出成绩'),
  ],
  FeatureId.evaluation: [
    (FeatureQueryView.summary, '全部'),
    (FeatureQueryView.evaluationPending, '待评课程'),
  ],
  FeatureId.signin: [
    (FeatureQueryView.summary, '全部'),
    (FeatureQueryView.signinPending, '可签到'),
    (FeatureQueryView.signinCompleted, '已签到'),
  ],
};

FeatureFilterKind? uiFeatureFilterKind(
  FeatureId feature,
  FeatureQuery? query, {
  required bool assignmentList,
  required bool bykcChosenDetail,
}) {
  final view = query?.view ?? FeatureQueryView.summary;
  if (assignmentList) return FeatureFilterKind.assignments;
  if (feature == FeatureId.bykc) {
    return view == FeatureQueryView.summary && !bykcChosenDetail
        ? FeatureFilterKind.bykc
        : null;
  }
  final views = _statusViews[feature];
  if (views == null || !views.any((item) => item.$1 == view)) return null;
  return FeatureFilterKind.status;
}

/// 与默认状态不同的条件数量；用于入口角标，避免条件生效却无从察觉。
int uiActiveFilterCount({
  required FeatureFilterKind kind,
  FeatureQuery? query,
  BykcCourseFilters bykcFilters = const BykcCourseFilters.defaults(),
  AssignmentListFilters? assignmentFilters,
}) => switch (kind) {
  FeatureFilterKind.status =>
    (query?.view ?? FeatureQueryView.summary) == FeatureQueryView.summary
        ? 0
        : 1,
  FeatureFilterKind.bykc =>
    (setEquals(bykcFilters.statuses, uiDefaultBykcStatuses) ? 0 : 1) +
        (bykcFilters.categories.isEmpty ? 0 : 1) +
        (bykcFilters.campuses.isEmpty ? 0 : 1),
  FeatureFilterKind.assignments => switch (assignmentFilters) {
    final f? =>
      (f.byStart ? 1 : 0) +
          (f.ascending ? 0 : 1) +
          (f.showExpired ? 1 : 0) +
          (f.onlyUnfinished ? 0 : 1),
    null => 0,
  },
};

/// 筛选面板正文：所有条件点选即生效，“恢复默认”一次撤销全部条件。
class FeatureFilterControls extends StatelessWidget {
  const FeatureFilterControls({
    required this.kind,
    required this.feature,
    required this.query,
    required this.details,
    this.onQuery,
    this.onLoadAcademicTerms,
    this.readCacheEpoch,
    this.bykcFilters = const BykcCourseFilters.defaults(),
    this.onBykcFiltersChanged,
    this.assignmentFilters,
    this.onAssignmentFiltersChanged,
    this.onLoadAssignmentHistory,
    super.key,
  });

  final FeatureFilterKind kind;
  final FeatureId feature;
  final FeatureQuery query;
  final List<FeatureDetail> details;
  final Future<void> Function(FeatureQuery query)? onQuery;
  final Future<FeatureResult> Function(bool forceRefresh)? onLoadAcademicTerms;

  /// 返回当前读取代次；学期对话框打开期间连接变化时不能套用旧选项。
  final ValueGetter<int>? readCacheEpoch;
  final BykcCourseFilters bykcFilters;
  final ValueChanged<BykcCourseFilters>? onBykcFiltersChanged;
  final AssignmentListFilters? assignmentFilters;
  final ValueChanged<AssignmentListFilters>? onAssignmentFiltersChanged;
  final VoidCallback? onLoadAssignmentHistory;

  int get activeCount => uiActiveFilterCount(
    kind: kind,
    query: query,
    bykcFilters: bykcFilters,
    assignmentFilters: assignmentFilters,
  );

  void reset() {
    switch (kind) {
      case FeatureFilterKind.status:
        if (query.view != FeatureQueryView.summary) {
          onQuery?.call(query.copyWith(view: FeatureQueryView.summary));
        }
      case FeatureFilterKind.bykc:
        onBykcFiltersChanged?.call(const BykcCourseFilters.defaults());
      case FeatureFilterKind.assignments:
        if (assignmentFilters case final filters?) {
          onAssignmentFiltersChanged?.call(
            AssignmentListFilters(isSpoc: filters.isSpoc),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (kind) {
      FeatureFilterKind.status => _status(context),
      FeatureFilterKind.bykc => _bykc(context),
      FeatureFilterKind.assignments => AssignmentFilterControls(
        filters: assignmentFilters!,
        onChanged: (value) => onAssignmentFiltersChanged?.call(value),
        onLoadHistory: onLoadAssignmentHistory,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        body,
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            if (kind == FeatureFilterKind.bykc)
              TextButton(
                onPressed: bykcFilters.statuses.isEmpty
                    ? null
                    : () => onBykcFiltersChanged?.call(
                        bykcFilters.copyWith(statuses: const {}),
                      ),
                child: const Text('状态不限'),
              ),
            TextButton(
              onPressed: activeCount == 0 ? null : reset,
              child: const Text('恢复默认'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> chips) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
        ),
      );

  Widget _status(BuildContext context) {
    final current = query.view;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(context, '状态', [
          for (final (view, label) in _statusViews[feature]!)
            ChoiceChip(
              label: Text(label),
              selected: current == view,
              // 已选项保持可用外观，重复点选不重新读取。
              onSelected: onQuery == null
                  ? null
                  : (_) {
                      if (current != view) {
                        onQuery!(query.copyWith(view: view));
                      }
                    },
            ),
        ]),
        if (feature == FeatureId.exam && onLoadAcademicTerms != null)
          _section(context, '学期', [
            ActionChip(
              avatar: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Text(query.term ?? '当前学期'),
              onPressed: onQuery == null ? null : () => _chooseTerm(context),
            ),
          ]),
      ],
    );
  }

  Future<void> _chooseTerm(BuildContext context) async {
    final epoch = readCacheEpoch?.call();
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => AcademicTermDialog(
        loader: onLoadAcademicTerms!,
        selected: query.term ?? '',
      ),
    );
    if (selected == null || !context.mounted) return;
    if (readCacheEpoch?.call() != epoch) {
      UbaaFeedback.show(
        context,
        '连接状态已变化，请重新选择学期。',
        kind: UbaaFeedbackKind.warning,
      );
      return;
    }
    if (selected == query.term) return;
    await onQuery?.call(query.copyWith(term: selected));
  }

  Widget _bykc(BuildContext context) {
    void update(BykcCourseFilters next) => onBykcFiltersChanged?.call(next);
    Set<T> toggled<T>(Set<T> values, T value, bool selected) =>
        selected ? {...values, value} : ({...values}..remove(value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(context, '课程状态', [
          for (final status in BykcCourseStatus.values)
            FilterChip(
              label: Text(uiBykcStatusLabel(status)),
              selected: bykcFilters.statuses.contains(status),
              onSelected: (selected) => update(
                bykcFilters.copyWith(
                  statuses: toggled(bykcFilters.statuses, status, selected),
                ),
              ),
            ),
        ]),
        _section(context, '课程类别', [
          for (final category in BykcCourseSubCategory.values.where(
            (value) => value != BykcCourseSubCategory.unknown,
          ))
            FilterChip(
              label: Text(category.displayName),
              selected: bykcFilters.categories.contains(category.displayName),
              onSelected: (selected) => update(
                bykcFilters.copyWith(
                  categories: toggled(
                    bykcFilters.categories,
                    category.displayName,
                    selected,
                  ),
                ),
              ),
            ),
        ]),
        _section(context, '适用校区', [
          for (final campus in uiBykcCampusOptions(
            details,
            bykcFilters.campuses,
          ))
            FilterChip(
              label: Text(campus),
              selected: bykcFilters.campuses.contains(campus),
              onSelected: (selected) => update(
                bykcFilters.copyWith(
                  campuses: toggled(bykcFilters.campuses, campus, selected),
                ),
              ),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            '只筛选已加载的课程，向下滚动会继续加载。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

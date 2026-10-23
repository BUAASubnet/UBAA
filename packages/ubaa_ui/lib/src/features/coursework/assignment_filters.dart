import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 展示条件独立于网络查询，父列表保留条件直到页面销毁。
class AssignmentListFilters {
  const AssignmentListFilters({
    this.isSpoc = false,
    this.byStart = false,
    this.ascending = true,
    this.showExpired = false,
    bool? onlyUnfinished,
  }) : onlyUnfinished = onlyUnfinished ?? !isSpoc;
  final bool isSpoc, byStart, ascending, showExpired, onlyUnfinished;

  AssignmentListFilters copyWith({
    bool? byStart,
    bool? ascending,
    bool? showExpired,
    bool? onlyUnfinished,
  }) {
    final expired = showExpired ?? this.showExpired;
    return AssignmentListFilters(
      isSpoc: isSpoc,
      byStart: byStart ?? this.byStart,
      ascending: ascending ?? this.ascending,
      showExpired: expired,
      onlyUnfinished:
          (isSpoc || !expired) && (onlyUnfinished ?? this.onlyUnfinished),
    );
  }

  List<FeatureDetail> apply(
    List<FeatureDetail> source,
    String search, {
    DateTime? now,
  }) {
    final query = search.trim().toLowerCase();
    final time = now ?? DateTime.now();
    final result = source.where((detail) {
      final p = _values(detail.presentation);
      // 渐进加载中尚无摘要的条目不冒充已确认的未完成作业。
      if (p == null) return false;
      if (p.isDetail) return true;
      if (query.isNotEmpty &&
          !detail.title.toLowerCase().contains(query) &&
          !p.course.toLowerCase().contains(query))
        return false;
      if (onlyUnfinished &&
          p.status != AssignmentSubmissionStatus.unsubmitted &&
          (isSpoc || p.status != AssignmentSubmissionStatus.partial))
        return false;
      final due = _date(p.due);
      return showExpired || due == null || !due.isBefore(time);
    }).toList();
    result.sort((left, right) {
      final a = _values(left.presentation)!;
      final b = _values(right.presentation)!;
      final at = _date(byStart ? a.start : a.due);
      final bt = _date(byStart ? b.start : b.due);
      var order = at == null
          ? (bt == null ? 0 : 1)
          : (bt == null ? -1 : at.compareTo(bt));
      if (order == 0) order = a.course.compareTo(b.course);
      if (order == 0) order = left.title.compareTo(right.title);
      return ascending ? order : -order;
    });
    return result;
  }

  ({
    String course,
    String? start,
    String? due,
    AssignmentSubmissionStatus status,
    bool isDetail,
  })?
  _values(FeaturePresentation? p) => switch (p) {
    SpocAssignmentPresentation p when isSpoc => (
      course: p.courseName,
      start: p.startTime,
      due: p.dueTime,
      status: p.status,
      isDetail: p.isDetail,
    ),
    JudgeAssignmentPresentation p when !isSpoc => (
      course: p.courseName,
      start: p.startTime,
      due: p.dueTime,
      status: p.status,
      isDetail: p.isDetail,
    ),
    _ => null,
  };

  static DateTime? _date(String? value) {
    final normalized = value?.trim().replaceAll(' ', 'T');
    if (normalized == null ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?$',
        ).hasMatch(normalized))
      return null;
    final date = DateTime.tryParse(normalized);
    // DateTime 会归一化不存在的日期；旧版将此类值视为未知。
    if (date == null ||
        date.toIso8601String().substring(0, 16) != normalized.substring(0, 16))
      return null;
    return date;
  }
}

class AssignmentFilterControls extends StatelessWidget {
  const AssignmentFilterControls({
    required this.filters,
    required this.onChanged,
    this.onLoadHistory,
  });
  final AssignmentListFilters filters;
  final ValueChanged<AssignmentListFilters> onChanged;
  final VoidCallback? onLoadHistory;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      const Text('排序字段'),
      Wrap(
        spacing: 8,
        children: [
          for (final (start, label) in [(false, '按截止时间'), (true, '按开始时间')])
            ChoiceChip(
              label: Text(label),
              selected: filters.byStart == start,
              onSelected: (_) => onChanged(filters.copyWith(byStart: start)),
            ),
        ],
      ),
      const SizedBox(height: 12),
      const Text('排序方向'),
      Wrap(
        spacing: 8,
        children: [
          for (final (ascending, label) in [(true, '升序'), (false, '降序')])
            ChoiceChip(
              label: Text(label),
              selected: filters.ascending == ascending,
              onSelected: (_) =>
                  onChanged(filters.copyWith(ascending: ascending)),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilterChip(
            label: Text(filters.isSpoc ? '仅显示未提交' : '仅显示未完成'),
            selected: filters.onlyUnfinished,
            onSelected: !filters.isSpoc && filters.showExpired
                ? null
                : (value) => onChanged(filters.copyWith(onlyUnfinished: value)),
          ),
          FilterChip(
            label: const Text('显示已截止'),
            selected: filters.showExpired,
            onSelected: (value) =>
                onChanged(filters.copyWith(showExpired: value)),
          ),
        ],
      ),
      if (filters.showExpired && onLoadHistory != null) ...[
        const SizedBox(height: 12),
        const Text('当前仅筛选已加载作业，历史作业尚未全部加载。'),
        TextButton.icon(
          onPressed: onLoadHistory,
          icon: const Icon(Icons.history),
          label: const Text('加载历史作业'),
        ),
      ],
    ],
  );
}

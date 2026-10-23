import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 展示条件独立于网络查询，父列表保留条件直到页面销毁。
class JudgeListFilters {
  const JudgeListFilters({
    this.byStart = false,
    this.ascending = true,
    this.showExpired = false,
    this.onlyUnfinished = true,
  });
  final bool byStart, ascending, showExpired, onlyUnfinished;

  JudgeListFilters copyWith({
    bool? byStart,
    bool? ascending,
    bool? showExpired,
    bool? onlyUnfinished,
  }) {
    final expired = showExpired ?? this.showExpired;
    return JudgeListFilters(
      byStart: byStart ?? this.byStart,
      ascending: ascending ?? this.ascending,
      showExpired: expired,
      onlyUnfinished: !expired && (onlyUnfinished ?? this.onlyUnfinished),
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
      final p = detail.presentation;
      // 渐进加载中尚无摘要的条目不冒充已确认的未完成作业。
      if (p is! JudgeAssignmentPresentation) return false;
      if (p.isDetail) return true;
      if (query.isNotEmpty &&
          !detail.title.toLowerCase().contains(query) &&
          !p.courseName.toLowerCase().contains(query))
        return false;
      if (onlyUnfinished &&
          p.status != AssignmentSubmissionStatus.unsubmitted &&
          p.status != AssignmentSubmissionStatus.partial)
        return false;
      final due = _date(p.dueTime);
      return showExpired || due == null || !due.isBefore(time);
    }).toList();
    result.sort((left, right) {
      final a = left.presentation! as JudgeAssignmentPresentation;
      final b = right.presentation! as JudgeAssignmentPresentation;
      final at = _date(byStart ? a.startTime : a.dueTime);
      final bt = _date(byStart ? b.startTime : b.dueTime);
      var order = at == null
          ? (bt == null ? 0 : 1)
          : (bt == null ? -1 : at.compareTo(bt));
      if (order == 0) order = a.courseName.compareTo(b.courseName);
      if (order == 0) order = left.title.compareTo(right.title);
      return ascending ? order : -order;
    });
    return result;
  }

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

class JudgeFilterControls extends StatelessWidget {
  const JudgeFilterControls({
    required this.filters,
    required this.onChanged,
    this.onLoadHistory,
  });
  final JudgeListFilters filters;
  final ValueChanged<JudgeListFilters> onChanged;
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
            label: const Text('仅显示未完成'),
            selected: filters.onlyUnfinished,
            onSelected: filters.showExpired
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

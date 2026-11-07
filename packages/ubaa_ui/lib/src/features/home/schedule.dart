import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/loading.dart';
import '../../shared/schedule_values.dart';
import '../../shared/text.dart';
import '../../common/state_panel.dart';
import '../../common/tag.dart';

typedef HomeScheduleRoute = ({String label, ConnectionMode? route});

class HomeScheduleSection extends StatelessWidget {
  const HomeScheduleSection({
    super.key,
    required this.state,
    required this.now,
    required this.onOpenSchedule,
    this.weekResult,
    this.onRetry,
    this.trailing,
  });
  final HomeScheduleState state;
  final DateTime now;
  final FeatureResult? weekResult;
  final VoidCallback onOpenSchedule;
  final VoidCallback? onRetry;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final day = state.day, tomorrow = state.tomorrow, remote = state.remote;
    final snapshot = state.snapshot;
    final courses =
        snapshot.details
            .where((d) => d.presentation is TodayCoursePresentation)
            .toList()
          ..sort((a, b) => uiCourseStart(a).compareTo(uiCourseStart(b)));
    final overview = snapshot.overview;
    final week = overview is HomeScheduleOverview
        ? homeWeekOn([overview.week], day)
        : homeWeekOn(
            weekResult?.details
                    .map((d) => d.presentation)
                    .whereType<WeekPresentation>() ??
                [],
            day,
          );
    final error = snapshot.error;
    final loading =
        snapshot.status == FeatureLoadStatus.loading &&
        (snapshot.evidence?.complete == false ||
            (snapshot.evidence == null && snapshot.updatedAt == null));
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Tooltip(
                message: '打开课表',
                child: InkWell(
                  onTap: onOpenSchedule,
                  child: Text(
                    tomorrow ? '明日课表' : '今日课表',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            if (trailing case final trailing?) trailing,
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${day.month}月${day.day}日 · ${uiWeekdays[day.weekday - 1]}${week == null ? '' : ' · 第${week.number}周'}',
        ),
        const SizedBox(height: 12),
        if (courses.isNotEmpty)
          for (final detail in courses)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CourseCard(detail: detail, day: day, now: now),
            )
        else if (loading)
          const LoadingPlaceholder(compact: true)
        else if (!remote &&
            snapshot.evidence == null &&
            snapshot.updatedAt == null &&
            snapshot.status == FeatureLoadStatus.idle)
          const SizedBox(height: 120)
        else
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(
                error != null
                    ? '课表读取失败，请重试'
                    : remote
                    ? snapshot.status == FeatureLoadStatus.idle
                          ? '暂无今日课表'
                          : tomorrow
                          ? '明天没有课程安排'
                          : '今天没有课程安排'
                    // 本地完整缓存与联网确认的空课表用同一文案，刷新后不跳变。
                    : (snapshot.evidence?.origin == DataOrigin.persisted &&
                              snapshot.evidence!.complete) ||
                          snapshot.status == FeatureLoadStatus.empty
                    ? '今天没有课程安排'
                    : snapshot.evidence?.complete == false
                    ? '课表暂未加载完整'
                    : '暂无课程安排',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: onOpenSchedule,
            ),
          ),
        if (error != null)
          UiInlineRetry(message: error.message, onRetry: onRetry),
      ],
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.detail,
    required this.day,
    required this.now,
  });
  final FeatureDetail detail;
  final DateTime day, now;
  @override
  Widget build(BuildContext context) {
    final course = detail.presentation! as TodayCoursePresentation;
    final status = homeCourseStatus(course, day, now);
    final theme = Theme.of(context);
    final active = status == '进行中';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    detail.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                UiTag(
                  status,
                  tone: active ? UiTagTone.primary : UiTagTone.neutral,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (uiNonBlank(course.time) case final time?)
              Text(
                // 上游时间段用连字符，统一成与待办一致的长横线。
                '时间：${time.replaceAll(RegExp(r'\s*[-—]\s*'), '–')}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (uiNonBlank(course.place) case final place?)
              Text(
                '地点：$place',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/loading.dart';
import '../../shared/schedule_values.dart';
import '../../shared/text.dart';
import '../../common/state_panel.dart';
import '../../common/tag.dart';
import '../../common/section.dart' show UiSectionHeader;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiSectionHeader(
          title: tomorrow ? '明日课表' : '今日课表',
          titleTooltip: '打开课表',
          onTitleTap: onOpenSchedule,
          subtitle:
              '${day.month}月${day.day}日 · ${uiWeekdays[day.weekday - 1]}${week == null ? '' : ' · 第${week.number}周'}',
          trailing: trailing,
        ),
        if (courses.isNotEmpty)
          for (final detail in courses)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CourseCard(
                detail: detail,
                day: day,
                now: now,
                onTap: onOpenSchedule,
              ),
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
    required this.onTap,
  });
  final FeatureDetail detail;
  final DateTime day, now;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final course = detail.presentation! as TodayCoursePresentation;
    final status = homeCourseStatus(course, day, now);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = status == '进行中';
    final ended = status == '已结束';
    // 上游时间段用连字符，拆成起止两行，与待办的长横线写法一致。
    final times = (uiNonBlank(course.time) ?? '')
        .split(RegExp(r'\s*[-—–~]\s*'))
        .where((t) => t.isNotEmpty)
        .toList();
    final place = uiNonBlank(course.place);
    final muted = colors.onSurfaceVariant;
    final card = Card(
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 时间列固定宽度，多张卡片的起止时间上下对齐。
              SizedBox(
                width: 76,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (times.isNotEmpty)
                        Text(
                          times.first,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      if (times.length > 1)
                        Text(
                          times.last,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: active ? colors.primary : colors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        detail.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (place != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.place_outlined, size: 16, color: muted),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                place,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // “未开始”是默认状态，不再逐张标注；进行中、已结束、时间待定等照常显示。
              if (status != '未开始')
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: UiTag(
                      status,
                      tone: active ? UiTagTone.primary : UiTagTone.neutral,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return ended ? Opacity(opacity: .6, child: card) : card;
  }
}

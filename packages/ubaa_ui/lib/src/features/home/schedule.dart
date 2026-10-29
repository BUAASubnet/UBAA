import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/loading.dart';
import '../../shared/schedule_values.dart';
import '../../shared/text.dart';

typedef HomeScheduleRoute = ({String label, ConnectionMode? route});

class HomeScheduleSection extends StatefulWidget {
  const HomeScheduleSection({
    super.key,
    required this.today,
    required this.now,
    required this.visible,
    required this.epoch,
    required this.businessEpoch,
    required this.onOpenSchedule,
    this.weekResult,
    this.onLoadDay,
    this.onRoute,
    this.trailing,
  });
  final ValueChanged<HomeScheduleRoute>? onRoute;

  /// 标题右侧的小控件（首页放最近使用的功能图标）。
  final Widget? trailing;
  final FeatureSnapshot today;
  final FeatureResult? weekResult;
  final DateTime now;
  final bool visible;
  final int epoch, businessEpoch;
  final VoidCallback onOpenSchedule;
  final Future<FeatureResult> Function(String, bool)? onLoadDay;
  @override
  State<HomeScheduleSection> createState() => _HomeScheduleSectionState();
}

class _HomeScheduleSectionState extends State<HomeScheduleSection> {
  final _days = <String, FeatureResult>{};
  final _attempted = <String>{}, _pending = <String>{};
  int _generation = 0;
  bool _force = false;
  HomeScheduleRoute? _reportedRoute;
  late final String _observedToday = homeDateKey(widget.now);

  @override
  void didUpdateWidget(covariant HomeScheduleSection old) {
    super.didUpdateWidget(old);
    if (old.epoch != widget.epoch ||
        old.businessEpoch != widget.businessEpoch) {
      _generation++;
      _attempted.clear();
      _pending.clear();
      _force = true;
      if (old.businessEpoch != widget.businessEpoch) _days.clear();
    }
  }

  void _queue(String date, {bool force = false}) {
    if (!widget.visible ||
        widget.onLoadDay == null ||
        _pending.contains(date) ||
        (!force && _attempted.contains(date)))
      return;
    _attempted.add(date);
    _pending.add(date);
    final refresh = force || _force;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.visible && generation == _generation) {
        unawaited(_read(date, refresh, generation));
      } else if (mounted && generation == _generation) {
        _attempted.remove(date);
        _pending.remove(date);
      }
    });
  }

  Future<void> _read(String date, bool force, int generation) async {
    _force = false;
    setState(() => _pending.add(date));
    FeatureResult result;
    try {
      result = await widget.onLoadDay!(date, force);
      if (result.error == null &&
          (result.overview is! HomeScheduleOverview ||
              (result.overview! as HomeScheduleOverview).date != date)) {
        result = const FeatureResult.failure(
          UiError(
            code: UbaaErrorCode.invalidInput,
            title: '课表暂不可用',
            message: '课表日期未确认',
          ),
        );
      }
    } on Object {
      result = const FeatureResult.failure(
        UiError(
          code: UbaaErrorCode.networkError,
          title: '课表加载失败',
          message: '请稍后重试',
          retryable: true,
        ),
      );
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _pending.remove(date);
      final old = _days[date];
      _days[date] =
          result.error != null && old?.overview is HomeScheduleOverview
          ? FeatureResult.partial(
              error: result.error!,
              details: old!.details,
              overview: old.overview,
              evidence: old.evidence,
              resolvedRoute: old.resolvedRoute,
            )
          : result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final todayKey = homeDateKey(widget.now);
    final original = widget.today;
    final matchesToday =
        (original.evidence?.scopeDate ?? _observedToday) == todayKey;
    final todayResult = matchesToday ? null : _days[todayKey];
    if (!matchesToday) _queue(todayKey);
    final todayCourses =
        (matchesToday
                ? original.details
                : todayResult?.details ?? const <FeatureDetail>[])
            .where((d) => d.presentation is TodayCoursePresentation)
            .toList();
    final complete = matchesToday
        ? original.evidence?.complete != false &&
              (original.status == FeatureLoadStatus.success ||
                  original.status == FeatureLoadStatus.empty ||
                  original.updatedAt != null)
        : todayResult?.overview is HomeScheduleOverview &&
              todayResult?.evidence?.complete != false;
    final tomorrow =
        complete &&
        widget.onLoadDay != null &&
        homeCoursesFinished(todayCourses, widget.now, widget.now);
    final day = DateTime(
      widget.now.year,
      widget.now.month,
      widget.now.day + (tomorrow ? 1 : 0),
    );
    final date = homeDateKey(day);
    if (tomorrow) _queue(date);
    final remote = tomorrow || !matchesToday;
    final result = remote ? _days[date] : null;
    final courses =
        (remote ? result?.details ?? const <FeatureDetail>[] : todayCourses)
            .where((d) => d.presentation is TodayCoursePresentation)
            .toList()
          ..sort((a, b) => uiCourseStart(a).compareTo(uiCourseStart(b)));
    final overview = result?.overview;
    final week = overview is HomeScheduleOverview
        ? homeWeekOn([overview.week], day)
        : homeWeekOn(
            widget.weekResult?.details
                    .map((d) => d.presentation)
                    .whereType<WeekPresentation>() ??
                [],
            day,
          );
    final error = remote ? result?.error : original.error;
    final loading = remote
        ? widget.onLoadDay != null &&
              (result == null || _pending.contains(date))
        : original.status == FeatureLoadStatus.loading &&
              (original.evidence?.complete == false ||
                  (original.evidence == null && original.updatedAt == null));
    final routeInfo = (
      label: tomorrow ? '明日课表' : '今日课表',
      route: remote ? result?.resolvedRoute : original.resolvedRoute,
    );
    if (widget.visible && routeInfo != _reportedRoute) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.visible && routeInfo != _reportedRoute) {
          _reportedRoute = routeInfo;
          widget.onRoute?.call(routeInfo);
        }
      });
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tomorrow ? '明日课表' : '今日课表',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (widget.trailing case final trailing?) trailing,
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
              child: _CourseCard(detail: detail, day: day, now: widget.now),
            )
        else if (loading)
          const LoadingPlaceholder(compact: true)
        else if (!remote &&
            original.evidence == null &&
            original.updatedAt == null &&
            original.status == FeatureLoadStatus.idle)
          const SizedBox(height: 120)
        else
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(
                error != null
                    ? '课表加载失败，请重试'
                    : remote
                    ? widget.onLoadDay == null
                          ? '暂无今日课表'
                          : tomorrow
                          ? '明天没有课程安排'
                          : '今天没有课程安排'
                    : original.evidence?.origin == DataOrigin.persisted &&
                          original.evidence!.complete
                    ? '暂无课程安排'
                    : original.status == FeatureLoadStatus.empty
                    ? '今天没有课程安排'
                    : original.evidence?.complete == false
                    ? '课表暂未加载完整'
                    : '暂无课程安排',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onOpenSchedule,
            ),
          ),
        if (error != null)
          Row(
            children: [
              Expanded(child: Text(error.message)),
              if (remote && widget.onLoadDay != null)
                TextButton(
                  onPressed: () {
                    _queue(date, force: true);
                    setState(() {});
                  },
                  child: const Text('重试'),
                ),
            ],
          ),
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: active
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
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

import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/controller/home/coordinator.dart';
import 'package:ubaa_ui/src/app/home.dart';
import 'package:ubaa_ui/src/features/home/schedule.dart';

class HomeHarness extends StatefulWidget {
  const HomeHarness({
    Key? key,
    required this.user,
    required this.snapshots,
    required this.onFeatureTap,
    required this.onRetryFeature,
    required this.onRefresh,
    required this.visible,
    required this.cacheEpoch,
    this.businessCacheEpoch = 0,
    required this.onTodoTap,
    this.onLoadSupplement,
    this.onLoadDaySchedule,
    this.onSignin,
    this.reminderSettings,
    this.onObserveProgress,
    this.gradeScoreNotice,
    this.gradeCheckRoute,
    this.onCheckGradeUpdates,
    this.onOpenGradeNotice,
    this.onDismissGradeNotice,
    this.writeReadbackNotice,
    this.homeClock,
    this.onProjectTodos,
    this.onViewAllTodos,
    this.agendaEpoch = 0,
    this.recentFeatures = const [],
    this.onSyncStatus,
    this.onPullRefresh,
    this.deferSupplements = false,
  }) : viewKey = key;
  final Key? viewKey;
  final Clock? homeClock;
  final HomeTodoReader? onProjectTodos;
  final VoidCallback? onViewAllTodos;
  final int agendaEpoch;
  final List<FeatureId> recentFeatures;

  /// 上报首页全部来源（含博雅已选、研讨室订单）是否刷新中及最早更新时间，供标题栏显示。
  final void Function(bool busy, DateTime? updatedAt)? onSyncStatus;

  /// 包装下拉触发的刷新，让外层知道这次刷新已有下拉指示器。
  final Future<void> Function(Future<void> Function() refresh)? onPullRefresh;

  /// 会话恢复期间暂缓补充来源，等首页刷新一起开始，避免排队后被刷新取消再重排。
  final bool deferSupplements;
  final Widget? writeReadbackNotice;
  final GradeScoreNotice? gradeScoreNotice;
  final ConnectionMode? gradeCheckRoute;
  final Future<void> Function()? onCheckGradeUpdates;
  final VoidCallback? onOpenGradeNotice, onDismissGradeNotice;
  final UserSummary? user;
  final Map<FeatureId, FeatureSnapshot> snapshots;
  final ValueChanged<FeatureId> onFeatureTap;
  final Future<void> Function(FeatureId) onRetryFeature;
  final Future<void> Function() onRefresh;
  final bool visible;
  final int cacheEpoch;
  final int businessCacheEpoch;
  final ValueChanged<HomeTodo> onTodoTap;
  final Future<WriteOutcome?> Function(SigninPerformAction)? onSignin;
  final Future<FeatureResult> Function(HomeSupplement, bool)? onLoadSupplement;
  final Future<FeatureResult> Function(String, bool)? onLoadDaySchedule;
  final YgdkReminderSettings? reminderSettings;
  final void Function(WeekPresentation, YgdkOverview)? onObserveProgress;
  @override
  State<HomeHarness> createState() => _HomeHarnessState();
}

class _HomeHarnessState extends State<HomeHarness> {
  late final HomeCoordinator model;
  bool hadReader = false;
  @override
  void initState() {
    super.initState();
    model = HomeCoordinator(
      loadSupplement: (s, f) =>
          widget.onLoadSupplement?.call(s, f) ??
          Future.value(const FeatureResult.empty()),
      loadDay: (d, f) => widget.onLoadDaySchedule!.call(d, f),
      project: (r) =>
          widget.onProjectTodos?.call(r) ??
          Future.value(HomeTodoProjection(const [])),
      refreshMain: () => widget.onRefresh(),
      retryMain: (f) => widget.onRetryFeature(f),
      now: () => (widget.homeClock ?? clock).now(),
      changed: () {
        if (!mounted) return;
        setState(() {});
        widget.onSyncStatus?.call(model.state.busy, model.state.updatedAt);
      },
    );
    sync();
  }

  void sync() {
    hadReader |= widget.onProjectTodos != null;
    model.update(
      owner: widget.businessCacheEpoch,
      snapshots: widget.snapshots,
      epoch: widget.cacheEpoch,
      agenda: widget.agendaEpoch,
      active: true,
      online: widget.visible && !widget.deferSupplements,
      blocked: hadReader && widget.onProjectTodos == null,
      foreground: widget.visible,
      readDays: widget.onLoadDaySchedule != null,
    );
    model.setReminder(widget.reminderSettings);
    model.tick();
  }

  @override
  void didUpdateWidget(covariant HomeHarness oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HomeView(
    key: widget.viewKey,
    state: model.state,
    onFeatureTap: widget.onFeatureTap,
    onRetryFeature: model.retry,
    onRefresh: model.refresh,
    visible: widget.visible,
    onTodoTap: widget.onTodoTap,
    onSignin: widget.onSignin,
    onObserveProgress: widget.onObserveProgress,
    gradeScoreNotice: widget.gradeScoreNotice,
    gradeCheckRoute: widget.gradeCheckRoute,
    onOpenGradeNotice: widget.onOpenGradeNotice,
    onDismissGradeNotice: widget.onDismissGradeNotice,
    writeReadbackNotice: widget.writeReadbackNotice,
    homeClock: widget.homeClock,
    onViewAllTodos: widget.onViewAllTodos,
    recentFeatures: widget.recentFeatures,
    onPullRefresh: widget.onPullRefresh,
  );
}

class HomeCalendarHarness extends StatefulWidget {
  const HomeCalendarHarness({
    super.key,
    required this.today,
    required this.now,
    required this.visible,
    required this.epoch,
    required this.businessEpoch,
    required this.onOpenSchedule,
    this.onLoadDay,
    this.onRoute,
  });
  final FeatureSnapshot today;
  final DateTime now;
  final bool visible;
  final int epoch, businessEpoch;
  final VoidCallback onOpenSchedule;
  final Future<FeatureResult> Function(String, bool)? onLoadDay;
  final ValueChanged<HomeScheduleRoute>? onRoute;
  @override
  State<HomeCalendarHarness> createState() => _HomeCalendarHarnessState();
}

class _HomeCalendarHarnessState extends State<HomeCalendarHarness> {
  late final HomeCoordinator model;
  HomeScheduleRoute? reported;
  @override
  void initState() {
    super.initState();
    model = HomeCoordinator(
      loadSupplement: (_, _) async => const FeatureResult.empty(),
      loadDay: (d, f) => widget.onLoadDay!(d, f),
      project: (_) async => HomeTodoProjection([]),
      refreshMain: () async {},
      retryMain: (_) async {},
      changed: () {
        if (!mounted) return;
        setState(() {});
        final s = model.state.schedule;
        final route = (
          label: s.tomorrow ? '明日课表' : '今日课表',
          route: s.snapshot.resolvedRoute,
        );
        if (route != reported) {
          reported = route;
          widget.onRoute?.call(route);
        }
      },
      now: () {
        final n = widget.now;
        return DateTime.utc(
          n.year,
          n.month,
          n.day,
          n.hour,
          n.minute,
          n.second,
        ).subtract(const Duration(hours: 8));
      },
    );
    sync();
  }

  void sync() {
    model.update(
      owner: widget.businessEpoch,
      snapshots: {FeatureId.schedule: widget.today},
      epoch: widget.epoch,
      agenda: 0,
      active: true,
      online: widget.visible,
      blocked: false,
      foreground: widget.visible,
      readDays: widget.onLoadDay != null,
    );
    model.tick();
  }

  @override
  void didUpdateWidget(covariant HomeCalendarHarness oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HomeScheduleSection(
    state: model.state.schedule,
    now: widget.now,
    onOpenSchedule: widget.onOpenSchedule,
    onRetry: () => model.retry(FeatureId.schedule),
  );
}

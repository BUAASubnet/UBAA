import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/theme.dart';
import '../common/section.dart';
import '../features/home/schedule.dart';
import '../features/home/todo_card.dart';
import '../features/home/todo_grid.dart';
import '../shared/loading.dart' show LoadingPlaceholder;
import '../features/grades/notice.dart' show GradeScoreBanner;
import '../shared/feature_icons.dart' show uiFeatureIcon;
import '../shared/refresh.dart' show PullToRefresh;

class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    required this.state,
    required this.onFeatureTap,
    required this.onRetryFeature,
    required this.onRefresh,
    required this.visible,
    required this.onTodoTap,
    this.onVisibilityChanged,
    this.onSignin,
    this.onObserveProgress,
    this.gradeScoreNotice,
    this.gradeCheckRoute,
    this.onOpenGradeNotice,
    this.onDismissGradeNotice,
    this.writeReadbackNotice,
    this.homeClock,
    this.onViewAllTodos,
    this.recentFeatures = const [],
    this.onPullRefresh,
  });
  final HomeState state;
  final ValueChanged<bool>? onVisibilityChanged;
  final ValueChanged<FeatureId> onFeatureTap;
  final Future<void> Function(FeatureId) onRetryFeature;
  final Future<void> Function() onRefresh;
  final bool visible;
  final ValueChanged<HomeTodo> onTodoTap;
  final Future<WriteOutcome?> Function(SigninPerformAction)? onSignin;
  final void Function(WeekPresentation, YgdkOverview)? onObserveProgress;
  final GradeScoreNotice? gradeScoreNotice;
  final ConnectionMode? gradeCheckRoute;
  final VoidCallback? onOpenGradeNotice, onDismissGradeNotice, onViewAllTodos;
  final Widget? writeReadbackNotice;
  final Clock? homeClock;
  final List<FeatureId> recentFeatures;
  final Future<void> Function(Future<void> Function() refresh)? onPullRefresh;
  @override
  State<HomeView> createState() => HomeViewState();
}

class HomeViewState extends State<HomeView> {
  void _reportVisibility() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) widget.onVisibilityChanged?.call(widget.visible);
  });
  @override
  void initState() {
    super.initState();
    _reportVisibility();
  }

  @override
  void didUpdateWidget(covariant HomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) _reportVisibility();
  }

  Future<void> refresh() => widget.onRefresh();
  DateTime get _now => widget.state.now;
  String? _signingTodo;
  final _completedSignins = <String>{};
  final _uncertainSignins = <String>{};
  String _signinKey(HomeTodo item) =>
      '${homeCampusTime(_now).toIso8601String().split('T').first}:${item.id}';

  Future<void> _signin(HomeTodo item) async {
    if (_signingTodo != null) return;
    final currentTime = (widget.homeClock ?? clock).now();
    if (homeDateKey(homeCampusTime(currentTime)) !=
        homeDateKey(homeCampusTime(_now))) {
      await _refreshSignin(item);
      return;
    }
    final action = item.signinAction;
    if (action == null || widget.onSignin == null) return;
    final key = _signinKey(item);
    setState(() => _signingTodo = item.id);
    try {
      final outcome = await widget.onSignin!(action);
      if (!mounted) return;
      setState(() {
        if (outcome?.operation == WriteOperation.signinPerform &&
            outcome?.result?.success == true &&
            outcome?.result?.outcomeUnknown == false) {
          _completedSignins.add(key);
        } else if (outcome?.result?.outcomeUnknown == true ||
            outcome?.error?.code == UbaaErrorCode.outcomeUnknown) {
          _uncertainSignins.add(key);
        }
      });
    } finally {
      if (mounted) setState(() => _signingTodo = null);
    }
  }

  Future<void> _refreshSignin(HomeTodo item) async {
    if (_signingTodo != null) return;
    setState(() => _signingTodo = item.id);
    try {
      await widget.onRetryFeature(FeatureId.signin);
      if (mounted &&
          widget.state.sources[FeatureId.signin]?.status ==
              FeatureLoadStatus.success) {
        setState(() => _uncertainSignins.remove(_signinKey(item)));
      }
    } finally {
      if (mounted) setState(() => _signingTodo = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final campusNow = homeCampusTime(_now);
    final sources = widget.state.sources;

    final weeks =
        widget.state.week?.details
            .map((d) => d.presentation)
            .whereType<WeekPresentation>()
            .toList() ??
        [];
    final week = weeks.length == 1 ? weeks.single : null;
    final tasks = widget.state.todos
        .where((task) => !_completedSignins.contains(_signinKey(task)))
        .toList();
    final overview = sources[FeatureId.ygdk]?.overview;
    if (widget.visible &&
        week != null &&
        overview is YgdkOverview &&
        sources[FeatureId.ygdk]?.status == FeatureLoadStatus.success) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.visible)
          widget.onObserveProgress?.call(week, overview);
      });
    }
    const features = [
      FeatureId.bykc,
      FeatureId.spoc,
      FeatureId.judge,
      FeatureId.cgyy,
      FeatureId.signin,
      FeatureId.ygdk,
      FeatureId.exam,
    ];
    final loading = features
        .where((f) => sources[f]?.status == FeatureLoadStatus.loading)
        .toList();
    final failed = features
        .where(
          (f) =>
              sources[f]?.status == FeatureLoadStatus.failure ||
              (sources[f]?.status == FeatureLoadStatus.stale &&
                  sources[f]?.error != null),
        )
        .toList();
    final courseSection = HomeScheduleSection(
      state: widget.state.schedule,
      weekResult: widget.state.week,
      now: campusNow,
      onRetry: () => widget.onRetryFeature(FeatureId.schedule),
      onOpenSchedule: () => widget.onFeatureTap(FeatureId.schedule),
      trailing: widget.recentFeatures.isEmpty
          ? null
          : _RecentFeatureIcons(
              features: widget.recentFeatures.take(4).toList(),
              onTap: widget.onFeatureTap,
            ),
    );
    Widget todoSection(int limit) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题字号与“今日课表”一致；刷新状态统一显示在标题栏右侧。
        Row(
          children: [
            Text(
              '待办',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (tasks.length > limit)
              TextButton(
                key: const ValueKey('home-todos-toggle'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: widget.onViewAllTodos,
                child: Text('查看全部（${tasks.length}）'),
              ),
          ],
        ),
        // 与课表日期行同高，两栏并排时首张卡片顶端对齐。
        const SizedBox(height: 4),
        Text(tasks.isEmpty ? '近期截止与提醒' : '近期 ${tasks.length} 项'),
        const SizedBox(height: 12),
        HomeTodoGrid(
          key: const ValueKey('home-todos'),
          children: [
            for (final task in tasks.take(limit))
              HomeTodoCard(
                item: task,
                now: campusNow,
                onTap: () => widget.onTodoTap(task),
                signing: _signingTodo == task.id,
                signinUncertain: _uncertainSignins.contains(_signinKey(task)),
                onSignin:
                    _signingTodo == null &&
                        task.signinAction != null &&
                        widget.onSignin != null &&
                        !_uncertainSignins.contains(_signinKey(task))
                    ? () => _signin(task)
                    : null,
                onRefreshSignin: _signingTodo == null
                    ? () => _refreshSignin(task)
                    : null,
              ),
          ],
        ),
        // 首次加载才占位；刷新时保留已有结果，进度只在标题栏右侧显示。
        // 还没算出过待办（如启动时等待会话恢复）时同样占位，不先说“没有待办”。
        if (tasks.isEmpty && !widget.state.projected)
          const LoadingPlaceholder(compact: true)
        else if (tasks.isEmpty &&
            loading.isNotEmpty &&
            loading.every(
              (f) =>
                  sources[f]?.updatedAt == null && sources[f]?.evidence == null,
            ))
          const LoadingPlaceholder(compact: true)
        else if (tasks.isEmpty &&
            features.any((f) => sources[f]?.status == FeatureLoadStatus.idle))
          const SizedBox(height: 120)
        else if (tasks.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(failed.isNotEmpty ? '暂无近期待办' : '当前没有待办'),
            ),
          ),
        if (widget.state.projectionFailure != null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('完成状态暂时无法显示，请刷新'),
          ),
        if (failed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              key: const ValueKey('home-source-warning'),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${failed.map(uiHomeFeatureLabel).join('、')}暂未加载',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                      onPressed: () => Future.wait([
                        for (final feature in failed)
                          widget.onRetryFeature(feature),
                      ]),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        for (final feature in features)
          if (sources[feature]?.evidence?.cacheFailure case final failure?
              when !failed.contains(feature) &&
                  sources[feature]?.status != FeatureLoadStatus.loading)
            if (uiCacheReadFailureText(failure) case final message?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${uiHomeFeatureLabel(feature)}：$message'),
              ),
        if (widget.state.week case final result?
            when result.error != null && !widget.state.busy)
          Row(
            children: [
              const Expanded(child: Text('当前周次未确定，暂不显示阳光打卡提醒')),
              TextButton(onPressed: widget.onRefresh, child: const Text('重试')),
            ],
          ),
      ],
    );
    return PullToRefresh(
      onRefresh: () => widget.onPullRefresh?.call(refresh) ?? refresh(),
      child: ListView(
        key: const ValueKey('home-scroll'),
        padding: UbaaTheme.pageInsets(context, top: 8),
        children: [
          if (widget.writeReadbackNotice case final notice?) ...[
            notice,
            const SizedBox(height: 12),
          ],
          if (widget.gradeScoreNotice case final notice?) ...[
            GradeScoreBanner(
              notice: notice,
              onOpen: widget.onOpenGradeNotice,
              onDismiss: widget.onDismissGradeNotice,
            ),
            const SizedBox(height: 12),
          ],
          LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth >=
                    MediaQuery.textScalerOf(context).scale(840)
                // 桌面宽度下课表与待办并排，减少整页只占上半屏的空白。
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: courseSection),
                      const SizedBox(width: 24),
                      Expanded(flex: 6, child: todoSection(6)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      courseSection,
                      // 课程卡片自带 12 的下边距，再留 12 与卡片间距相称。
                      const SizedBox(height: 12),
                      todoSection(4),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// 只有存储空间不足时学生能自行处理；其他保存失败不影响已显示内容，不提示。
String? uiCacheReadFailureText(CacheMaintenanceFailure failure) =>
    failure == CacheMaintenanceFailure.capacity ? '手机存储空间不足，本次内容未能保存。' : null;

class FeatureGridView extends StatelessWidget {
  const FeatureGridView({
    required this.snapshots,
    required this.onFeatureTap,
    required this.onRetryFeature,
    required this.features,
    this.onOpenIhome,
    this.onOpenBhpan,
  });
  final Map<FeatureId, FeatureSnapshot> snapshots;
  final ValueChanged<FeatureId> onFeatureTap;
  final Future<void> Function(FeatureId) onRetryFeature;
  final List<FeatureId> features;
  final VoidCallback? onOpenIhome;
  final VoidCallback? onOpenBhpan;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: UbaaTheme.pageInsets(context, top: 8),
        sliver: SliverToBoxAdapter(child: _grid()),
      ),
    ],
  );

  Widget _grid() => UiAdaptiveGrid(
    minItemWidth: 400,
    maxColumns: 2,
    children: [
      if (onOpenIhome != null)
        UiEntryCard(
          title: 'iHome',
          icon: Icons.forum_outlined,
          subtitle: '校园诉求、回复与公告',
          onTap: onOpenIhome!,
        ),
      if (onOpenBhpan != null)
        UiEntryCard(
          title: '北航云盘',
          icon: Icons.cloud_outlined,
          subtitle: '文档库、文件管理、分享与回收站',
          onTap: onOpenBhpan!,
        ),
      for (final feature in features)
        Semantics(
          container: true,
          button: true,
          excludeSemantics: true,
          onTap: () => onFeatureTap(feature),
          label:
              '${feature.title}：${snapshots[feature]?.summary ?? feature.description}。点击查看详情',
          child: UiEntryCard(
            title: feature.title,
            icon: uiFeatureIcon(feature),
            subtitle: feature.description,
            onTap: () => onFeatureTap(feature),
          ),
        ),
    ],
  );
}

/// 最近使用的功能：今日课表标题右侧的一排小图标，长按显示名称。
class _RecentFeatureIcons extends StatelessWidget {
  const _RecentFeatureIcons({required this.features, required this.onTap});
  final List<FeatureId> features;
  final ValueChanged<FeatureId> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, feature) in features.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          IconButton.filledTonal(
            key: ValueKey('recent-${feature.name}'),
            tooltip: feature.title,
            style: IconButton.styleFrom(
              minimumSize: const Size(36, 36),
              fixedSize: const Size(36, 36),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
            ),
            iconSize: 18,
            onPressed: () => onTap(feature),
            icon: Icon(uiFeatureIcon(feature)),
          ),
        ],
      ],
    );
  }
}

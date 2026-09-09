part of '../widgets.dart';

class _HomeView extends StatefulWidget {
  const _HomeView({
    required this.user,
    required this.snapshots,
    required this.onFeatureTap,
    required this.onRetryFeature,
    required this.onRefresh,
    required this.visible,
    required this.cacheEpoch,
    required this.onTodoTap,
    this.onLoadSupplement,
    this.onSignin,
    this.reminderSettings,
    this.onObserveProgress,
    this.onRoutes,
    this.gradeScoreNotice,
    this.gradeCheckRoute,
    this.onCheckGradeUpdates,
    this.onOpenGradeNotice,
    this.onDismissGradeNotice,
  });
  final ValueChanged<Map<String, ConnectionMode>>? onRoutes;
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
  final ValueChanged<HomeTodo> onTodoTap;
  final Future<void> Function(SigninPerformAction)? onSignin;
  final Future<FeatureResult> Function(HomeSupplement, bool)? onLoadSupplement;
  final YgdkReminderSettings? reminderSettings;
  final void Function(WeekPresentation, YgdkOverview)? onObserveProgress;
  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  final _supplements = <HomeSupplement, FeatureResult>{};
  final _loading = <HomeSupplement>{};
  int _generation = 0;
  bool _scheduled = false;
  int? _gradeCheckEpoch;
  late final Timer _clock;
  DateTime _now = clock.now();
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && widget.visible) setState(() => _now = clock.now());
    });
  }

  @override
  void didUpdateWidget(covariant _HomeView old) {
    super.didUpdateWidget(old);
    if (old.cacheEpoch != widget.cacheEpoch) {
      _generation++;
      _supplements.clear();
      _loading.clear();
    }
    if (!old.visible && widget.visible) _now = clock.now();
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  void _scheduleLoads() {
    if (_scheduled ||
        !widget.visible ||
        widget.onLoadSupplement == null ||
        !widget.snapshots.values.any((s) => s.updatedAt != null))
      return;
    final needed = HomeSupplement.values
        .where((s) => !_supplements.containsKey(s) && !_loading.contains(s))
        .toList();
    if (needed.isEmpty) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && widget.visible) {
        for (final source in needed) {
          unawaited(_load(source));
        }
      }
    });
  }

  Future<void> _load(HomeSupplement source, {bool force = false}) async {
    final load = widget.onLoadSupplement;
    if (load == null || _loading.contains(source)) return;
    final generation = _generation;
    setState(() => _loading.add(source));
    FeatureResult result;
    try {
      result = await load(source, force);
    } on Object {
      result = const FeatureResult.failure(
        UiError(
          code: UbaaErrorCode.internalError,
          title: '加载失败',
          message: '待办来源读取失败',
        ),
      );
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading.remove(source);
      _supplements[source] = result;
    });
  }

  Map<FeatureId, FeatureSnapshot> _sources() {
    final sources = Map<FeatureId, FeatureSnapshot>.of(widget.snapshots);
    for (final (source, feature, view) in [
      (
        HomeSupplement.bykcChosen,
        FeatureId.bykc,
        FeatureQueryView.bykcChosenCourses,
      ),
      (HomeSupplement.cgyyOrders, FeatureId.cgyy, FeatureQueryView.cgyyOrders),
    ]) {
      final result = _supplements[source];
      sources[feature] = FeatureSnapshot(
        feature: feature,
        status: _loading.contains(source)
            ? FeatureLoadStatus.loading
            : result == null
            ? FeatureLoadStatus.idle
            : result.error != null
            ? FeatureLoadStatus.failure
            : result.isEmpty
            ? FeatureLoadStatus.empty
            : FeatureLoadStatus.success,
        details: result?.details ?? const [],
        error: result?.error,
        resolvedRoute: result?.resolvedRoute,
        pagination: result?.pagination,
        readContext: FeatureReadContext(
          requestRevision: widget.cacheEpoch,
          query: FeatureQuery(view: view),
        ),
      );
    }
    return sources;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleLoads();
    if (widget.visible &&
        widget.onCheckGradeUpdates != null &&
        _gradeCheckEpoch != widget.cacheEpoch &&
        widget.snapshots.values.any((s) => s.updatedAt != null)) {
      final epoch = widget.cacheEpoch;
      _gradeCheckEpoch = epoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.visible && widget.cacheEpoch == epoch) {
          unawaited(widget.onCheckGradeUpdates!());
        } else if (mounted && _gradeCheckEpoch == epoch) {
          _gradeCheckEpoch = null;
        }
      });
    }
    final schedule = widget.snapshots[FeatureId.schedule]!;
    final today =
        schedule.details
            .where((d) => d.presentation is TodayCoursePresentation)
            .toList()
          ..sort((a, b) => _courseStart(a).compareTo(_courseStart(b)));
    final sources = _sources();
    if (widget.visible) {
      final routes = <String, ConnectionMode>{
        if (schedule.resolvedRoute case final route?) '今日课表': route,
        if (widget.gradeScoreNotice case final notice?) '成绩更新': notice.route,
        if (widget.gradeCheckRoute case final route?) '成绩检查': route,
        for (final feature in [
          FeatureId.bykc,
          FeatureId.spoc,
          FeatureId.judge,
          FeatureId.cgyy,
          FeatureId.signin,
          FeatureId.ygdk,
        ])
          if (sources[feature]?.resolvedRoute case final route?)
            _homeLabel(feature): route,
        if (_supplements[HomeSupplement.currentWeek]?.resolvedRoute
            case final route?)
          '当前周次': route,
      };
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.visible) widget.onRoutes?.call(routes);
      });
    }

    final weeks =
        _supplements[HomeSupplement.currentWeek]?.details
            .map((d) => d.presentation)
            .whereType<WeekPresentation>()
            .toList() ??
        [];
    final week = weeks.length == 1 ? weeks.single : null;
    final reminder = widget.reminderSettings;
    final tasks = buildHomeTodos(
      snapshots: sources,
      now: _now,
      currentWeek: week,
      ygdkReminderEnabled: reminder?.enabled ?? false,
      ygdkWeekDone:
          week != null &&
          reminder?.weekDoneKey == '${week.responseTerm}:${week.number}',
      ygdkTermDone: week != null && reminder?.termDoneKey == week.responseTerm,
    );
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
    ];
    final loading = features
        .where(
          (f) =>
              sources[f]?.status == FeatureLoadStatus.loading ||
              sources[f]?.status == FeatureLoadStatus.idle,
        )
        .toList();
    final failed = features
        .where(
          (f) =>
              sources[f]?.status == FeatureLoadStatus.failure ||
              sources[f]?.status == FeatureLoadStatus.stale,
        )
        .toList();
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '今日课表',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text('${_now.month}月${_now.day}日'),
          const SizedBox(height: 12),
          if (widget.gradeScoreNotice case final notice?) ...[
            _GradeScoreBanner(
              notice: notice,
              onOpen: widget.onOpenGradeNotice,
              onDismiss: widget.onDismissGradeNotice,
            ),
            const SizedBox(height: 12),
          ],
          if (today.isNotEmpty)
            for (final detail in today)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _HomeCourseCard(detail: detail),
              )
          else
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(
                  schedule.status == FeatureLoadStatus.empty
                      ? '今天没有课程安排'
                      : _homeSummary(schedule),
                ),
                subtitle: const Text('打开课表查询查看课程安排'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.onFeatureTap(FeatureId.schedule),
              ),
            ),
          if (today.isNotEmpty && schedule.status == FeatureLoadStatus.stale)
            const Text('课表刷新失败，以上为上次成功加载的数据。'),
          const SizedBox(height: 16),
          Text(
            '待办区',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            loading.isEmpty
                ? '聚合近期需要处理的课程和任务'
                : '正在加载 ${loading.map(_homeLabel).join('、')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (failed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '部分内容加载失败：${failed.map(_homeLabel).join('、')}，已显示其余待办。',
              ),
            ),
          if (_supplements[HomeSupplement.currentWeek] case final result?
              when result.error != null || result.isEmpty)
            Row(
              children: [
                const Expanded(child: Text('当前周次未确定，暂不显示阳光提醒')),
                TextButton(
                  onPressed: () =>
                      _load(HomeSupplement.currentWeek, force: true),
                  child: const Text('重试'),
                ),
              ],
            ),
          const SizedBox(height: 12),
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _HomeTodoCard(
                item: task,
                onTap: () => widget.onTodoTap(task),
                onSignin: task.signinAction != null && widget.onSignin != null
                    ? () => widget.onSignin!(task.signinAction!)
                    : null,
              ),
            ),
          if (tasks.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  loading.isNotEmpty
                      ? '待办正在后台加载'
                      : failed.isNotEmpty
                      ? '已加载的来源中暂无近期待办'
                      : '当前没有待办',
                ),
              ),
            ),
          for (final feature in failed)
            ListTile(
              dense: true,
              title: Text(
                '${_homeLabel(feature)}：${_homeSummary(sources[feature]!)}',
              ),
              trailing: TextButton(
                onPressed: () => feature == FeatureId.bykc
                    ? _load(HomeSupplement.bykcChosen, force: true)
                    : feature == FeatureId.cgyy
                    ? _load(HomeSupplement.cgyyOrders, force: true)
                    : widget.onRetryFeature(feature),
                child: const Text('重试'),
              ),
            ),
        ],
      ),
    );
  }
}

int _courseStart(FeatureDetail detail) {
  final value = (detail.presentation as TodayCoursePresentation).time ?? '';
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
  if (match == null) return 9999;
  final hour = int.parse(match[1]!), minute = int.parse(match[2]!);
  return hour < 24 && minute < 60 ? hour * 60 + minute : 9999;
}

String _homeLabel(FeatureId feature) => switch (feature) {
  FeatureId.bykc => '博雅',
  FeatureId.spoc => 'SPOC',
  FeatureId.judge => '希冀',
  FeatureId.cgyy => '研讨室',
  FeatureId.signin => '签到',
  FeatureId.ygdk => '阳光打卡',
  _ => feature.title,
};
String _homeSummary(FeatureSnapshot snapshot) => switch (snapshot.status) {
  FeatureLoadStatus.idle => '尚未查询',
  FeatureLoadStatus.loading => '正在加载…',
  FeatureLoadStatus.success => snapshot.summary ?? '已加载',
  FeatureLoadStatus.empty => '当前条件暂无结果',
  FeatureLoadStatus.stale => '刷新失败，显示上次结果',
  FeatureLoadStatus.failure => '加载失败',
};

class _HomeTodoCard extends StatelessWidget {
  const _HomeTodoCard({required this.item, required this.onTap, this.onSignin});
  final HomeTodo item;
  final VoidCallback onTap;
  final Future<void> Function()? onSignin;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.navigation == null ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                _featureIcon(item.feature),
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _homeChip(context, _homeLabel(item.feature)),
                        _homeChip(context, item.statusLabel),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.timeLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              if (item.feature == FeatureId.signin) ...[
                const SizedBox(width: 8),
                FilledButton(onPressed: onSignin, child: const Text('签到')),
              ] else if (item.navigation != null)
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeChip(BuildContext context, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    ),
  );
}

class _HomeCourseCard extends StatelessWidget {
  const _HomeCourseCard({required this.detail});
  final FeatureDetail detail;
  @override
  Widget build(BuildContext context) {
    final course = detail.presentation! as TodayCoursePresentation;
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              detail.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_nonBlank(course.time) case final time?)
                        Text(
                          '时间：$time',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (_nonBlank(course.place) case final place?)
                        Text(
                          '地点：$place',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_nonBlank(detail.subtitle) case final shortName?) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 100),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        shortName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureGridView extends StatelessWidget {
  const _FeatureGridView({
    required this.snapshots,
    required this.onFeatureTap,
    required this.onRetryFeature,
  });

  final Map<FeatureId, FeatureSnapshot> snapshots;
  final ValueChanged<FeatureId> onFeatureTap;
  final Future<void> Function(FeatureId) onRetryFeature;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: <Widget>[
      SliverPadding(
        padding: EdgeInsets.all(
          UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width),
        ),
        sliver: _FeatureGridSliver(
          snapshots: snapshots,
          onFeatureTap: onFeatureTap,
          onRetryFeature: onRetryFeature,
        ),
      ),
    ],
  );
}

class _FeatureGridSliver extends StatelessWidget {
  const _FeatureGridSliver({
    required this.snapshots,
    required this.onFeatureTap,
    required this.onRetryFeature,
    this.features = ordinaryFeatureIds,
  });

  final Map<FeatureId, FeatureSnapshot> snapshots;
  final ValueChanged<FeatureId> onFeatureTap;
  final Future<void> Function(FeatureId) onRetryFeature;
  final List<FeatureId> features;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final columns = (constraints.crossAxisExtent / 220).floor().clamp(2, 5);
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      return SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: 184 * scale.clamp(1.0, 2.0),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: features.length,
        itemBuilder: (context, index) {
          final feature = features[index];
          return _FeatureCard(
            feature: feature,
            snapshot: snapshots[feature]!,
            onTap: () => onFeatureTap(feature),
            onRetry: () => onRetryFeature(feature),
          );
        },
      );
    },
  );
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.feature,
    required this.snapshot,
    required this.onTap,
    required this.onRetry,
  });

  final FeatureId feature;
  final FeatureSnapshot snapshot;
  final VoidCallback onTap;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      button: true,
      label:
          '${feature.title}：${snapshot.summary ?? feature.description}。点击查看详情',
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerHigh,
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  _featureIcon(feature),
                  size: 40,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  feature.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  feature.description,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdvancedFeaturesView extends StatelessWidget {
  const _AdvancedFeaturesView({
    required this.snapshots,
    required this.onFeatureTap,
    required this.onRetryFeature,
  });

  final Map<FeatureId, FeatureSnapshot> snapshots;
  final ValueChanged<FeatureId> onFeatureTap;
  final Future<void> Function(FeatureId) onRetryFeature;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: <Widget>[
      SliverPadding(
        padding: EdgeInsets.all(
          UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width),
        ),
        sliver: _FeatureGridSliver(
          features: advancedFeatureIds,
          snapshots: snapshots,
          onFeatureTap: onFeatureTap,
          onRetryFeature: onRetryFeature,
        ),
      ),
    ],
  );
}

IconData _featureIcon(FeatureId feature) => switch (feature) {
  FeatureId.schedule => Icons.calendar_today,
  FeatureId.exam => Icons.assignment_outlined,
  FeatureId.grades => Icons.grade,
  FeatureId.bykc => Icons.school,
  FeatureId.classroom => Icons.meeting_room,
  FeatureId.spoc => Icons.assignment_turned_in,
  FeatureId.judge => Icons.code,
  FeatureId.libbook => Icons.event_seat,
  FeatureId.signin => Icons.how_to_reg,
  FeatureId.cgyy => Icons.date_range,
  FeatureId.ygdk => Icons.wb_sunny,
  FeatureId.evaluation => Icons.assignment_turned_in,
};

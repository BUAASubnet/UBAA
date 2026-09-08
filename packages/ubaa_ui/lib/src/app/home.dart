part of '../widgets.dart';

class _HomeView extends StatelessWidget {
  const _HomeView({
    required this.user,
    required this.snapshots,
    required this.onFeatureTap,
    required this.onRetryFeature,
    required this.onRefresh,
  });

  final UserSummary? user;
  final Map<FeatureId, FeatureSnapshot> snapshots;
  final ValueChanged<FeatureId> onFeatureTap;
  final Future<void> Function(FeatureId) onRetryFeature;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final schedule = snapshots[FeatureId.schedule]!;
    final todayQuery =
        schedule.readContext?.query == null ||
        schedule.readContext?.query?.view == FeatureQueryView.scheduleToday;
    final today = todayQuery
        ? schedule.details
              .where((detail) => detail.presentation is TodayCoursePresentation)
              .toList()
        : <FeatureDetail>[];
    final tasks = <(FeatureId, FeatureDetail, String, String, DateTime)>[];
    final now = DateTime.now();
    for (final feature in [FeatureId.spoc, FeatureId.judge]) {
      final snapshot = snapshots[feature]!;
      if (snapshot.status != FeatureLoadStatus.success &&
          snapshot.status != FeatureLoadStatus.stale)
        continue;
      if (snapshot.readContext?.query != null &&
          snapshot.readContext?.query?.view != FeatureQueryView.summary)
        continue;
      for (final detail in snapshot.details) {
        final p = detail.presentation;
        String? due;
        String? course;
        bool pending = false;
        if (p is SpocAssignmentPresentation && !p.isDetail) {
          due = p.dueTime;
          course = p.courseName;
          final start = DateTime.tryParse(p.startTime ?? '');
          pending =
              p.status == AssignmentSubmissionStatus.unsubmitted &&
              (start == null || !start.isAfter(now));
        } else if (p is JudgeAssignmentPresentation && !p.isDetail) {
          due = p.dueTime;
          course = p.courseName;
          pending =
              p.status == AssignmentSubmissionStatus.unsubmitted ||
              p.status == AssignmentSubmissionStatus.partial;
        }
        final end = DateTime.tryParse(due ?? '');
        if (pending && end != null && end.isAfter(now))
          tasks.add((feature, detail, course ?? '', due!, end));
      }
    }
    tasks.sort((a, b) => a.$5.compareTo(b.$5));
    return RefreshIndicator(
      onRefresh: onRefresh,
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
          Text(
            '${now.month}月${now.day}日',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
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
                title: Text(todayQuery ? _summary(schedule) : '今日课表尚未加载'),
                subtitle: const Text('打开课表查询查看课程安排'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onFeatureTap(FeatureId.schedule),
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
          const SizedBox(height: 12),
          for (final task in tasks)
            Card(
              child: ListTile(
                leading: Icon(_featureIcon(task.$1)),
                title: Text(task.$2.title),
                subtitle: Text('${task.$3} · 待完成\n截止 ${task.$4}'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onFeatureTap(task.$1),
              ),
            ),
          if (tasks.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('当前已加载的课程作业中暂无近期待办'),
              ),
            ),
          for (final feature in [FeatureId.spoc, FeatureId.judge])
            if (snapshots[feature]!.status != FeatureLoadStatus.success &&
                snapshots[feature]!.status != FeatureLoadStatus.empty)
              ListTile(
                dense: true,
                title: Text(
                  '${feature.title}：${_summary(snapshots[feature]!)}',
                ),
                onTap: () => onFeatureTap(feature),
              ),
        ],
      ),
    );
  }

  String _summary(FeatureSnapshot snapshot) => switch (snapshot.status) {
    FeatureLoadStatus.idle => '尚未查询',
    FeatureLoadStatus.loading => '正在加载…',
    FeatureLoadStatus.success => snapshot.summary ?? '已加载，进入功能查看',
    FeatureLoadStatus.empty => '当前条件暂无结果',
    FeatureLoadStatus.stale => '${snapshot.summary ?? '上次结果'}（刷新失败）',
    FeatureLoadStatus.failure => '加载失败，请进入功能重试',
  };
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

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
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Text(
              '你好，${user?.preferredName ?? '同学'}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: _FeatureGridSliver(
            snapshots: snapshots,
            onFeatureTap: onFeatureTap,
            onRetryFeature: onRetryFeature,
          ),
        ),
      ],
    ),
  );
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
        padding: const EdgeInsets.all(16),
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
  Widget build(BuildContext context) => SliverGrid.builder(
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 360,
      mainAxisExtent: 160,
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
    final isFailure = snapshot.status == FeatureLoadStatus.failure;
    final isStale = snapshot.status == FeatureLoadStatus.stale;
    return Semantics(
      container: true,
      button: true,
      label: '$featureLabel：${_statusText(snapshot)}。点击查看详情',
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      _featureIcon(feature),
                      size: 40,
                      color: colorScheme.primary,
                    ),
                    const Spacer(),
                    if (snapshot.status == FeatureLoadStatus.loading)
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (isFailure || isStale)
                      IconButton(
                        tooltip: '重试',
                        onPressed: () => onRetry(),
                        icon: Icon(Icons.refresh, color: colorScheme.error),
                      )
                    else if (snapshot.status == FeatureLoadStatus.success)
                      Icon(Icons.check_circle, color: colorScheme.primary),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  feature.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    _statusText(snapshot),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isFailure
                          ? colorScheme.error
                          : isStale
                          ? colorScheme.tertiary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (snapshot.resolvedRoute case final route?)
                  Text(
                    '实际路线：${route.label}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
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

  String get featureLabel => feature.title;

  String _statusText(FeatureSnapshot snapshot) => switch (snapshot.status) {
    FeatureLoadStatus.idle => feature.description,
    FeatureLoadStatus.loading => '正在加载…',
    FeatureLoadStatus.success => snapshot.summary ?? '已加载，点击查看详情',
    FeatureLoadStatus.empty => '暂无数据',
    FeatureLoadStatus.stale => '${snapshot.summary ?? '已显示上次数据'}（刷新失败，可重试）',
    FeatureLoadStatus.failure => snapshot.error?.message ?? '加载失败，请重试',
  };
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
        padding: const EdgeInsets.all(16),
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
  FeatureId.cgyy => Icons.sports_gymnastics,
  FeatureId.ygdk => Icons.wb_sunny,
  FeatureId.evaluation => Icons.assignment_turned_in,
};

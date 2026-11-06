part of 'view.dart';

extension _AgendaDataSheet on AgendaViewState {
  Future<void> _showDataSheet() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => bound(
      // 跟随日程页重建，刷新完成后面板内容同步更新。
      ValueListenableBuilder<int>(
        valueListenable: sheetTick,
        builder: (context, _, _) {
          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          Widget section(String text) => Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(
              text,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
          Widget note(IconData icon, String text) => Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          );
          final data = result;
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('数据与同步', style: theme.textTheme.titleLarge),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  if (available && service.supportsSync) ...[
                    section('云端同步'),
                    _syncStatusCard(),
                  ],
                  if (data != null &&
                      data.sources.every((s) => s.observations.isEmpty)) ...[
                    section('学校数据'),
                    Container(
                      key: const ValueKey('agenda-school-empty'),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          colors.tertiary.withValues(alpha: .08),
                          colors.surfaceContainerLow,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: colors.tertiary.withValues(alpha: .15),
                              shape: BoxShape.circle,
                            ),
                            child: schoolRefreshing
                                ? Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: colors.tertiary,
                                    ),
                                  )
                                : Icon(
                                    Icons.cloud_download_outlined,
                                    size: 22,
                                    color: colors.tertiary,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  schoolRefreshing ? '正在获取学校数据' : '还没有学校数据',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '课程、考试、作业等需要先从学校刷新一次；刷新后仍为空时，可到首页查看各来源状态。',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (data != null) ...[
                    const SizedBox(height: 4),
                    AgendaCacheStatus(
                      sources: data.sources,
                      route: widget.route,
                      now: agendaTime(now),
                    ),
                    if (data.schoolCacheFailure != null ||
                        data.sources.any(
                          (s) =>
                              s.feature != AgendaFeature.schedule &&
                              s.missingScopes.isNotEmpty,
                        ))
                      note(Icons.info_outline, '部分来源待补全，已有事项仍可查看。'),
                    if (data.sources.any(
                      (s) =>
                          s.feature == AgendaFeature.schedule &&
                          (s.missingScopes.isNotEmpty ||
                              s.semesterImported != true),
                    ))
                      note(
                        Icons.calendar_month_outlined,
                        '目前只缓存了已查看周的课表，导入整学期课表后可查看全部周。',
                      ),
                    if (data.sources.any((s) => s.unprojectableCount > 0))
                      note(Icons.info_outline, '部分学校事项缺少必要字段，未加入时间线。'),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: available && !schoolRefreshing
                              ? () => unawaited(refreshSchool())
                              : null,
                          icon: schoolRefreshing
                              ? const LoadingGlyph(dimension: 16)
                              : const Icon(Icons.refresh, size: 18),
                          label: Text(schoolRefreshing ? '正在刷新' : '刷新学校日程'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: available
                              ? () {
                                  Navigator.pop(context);
                                  importSchedule();
                                }
                              : null,
                          icon: const Icon(
                            Icons.calendar_month_outlined,
                            size: 18,
                          ),
                          label: const Text('导入整学期课表'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _buildStatusLine() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final data = result;
    final noSchool =
        data != null && data.sources.every((s) => s.observations.isEmpty);
    // 课表其他周未缓存属于正常情况，提示导入整学期而不是警告。
    final partial =
        data != null &&
        (data.schoolCacheFailure != null ||
            data.sources.any(
              (s) =>
                  s.feature != AgendaFeature.schedule &&
                  s.missingScopes.isNotEmpty,
            ));
    // 正常状态不占位；只有学校事项需要处理时提示，详情在「数据与同步」里。
    final warn = noSchool || partial;
    if (!warn) return const SizedBox.shrink();
    final text = noSchool ? '学校事项待刷新' : '部分来源待补全';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Material(
        color: colors.tertiaryContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: const ValueKey('agenda-data-notice'),
          borderRadius: BorderRadius.circular(10),
          onTap: dataSheet,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: colors.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onTertiaryContainer,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

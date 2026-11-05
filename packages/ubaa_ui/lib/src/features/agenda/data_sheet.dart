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
                        child: Text(
                          '数据与同步',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
                  if (data != null) ...[
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
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
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
    final syncOn = available && service.supportsSync && service.syncEnabled;
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
    final semester =
        data != null &&
        data.sources.any(
          (s) =>
              s.feature == AgendaFeature.schedule && s.semesterImported != true,
        );
    final warn = noSchool || partial;
    final text = [
      syncOn ? '已开启云端同步' : '仅保存在本机',
      if (noSchool)
        '学校事项待刷新'
      else if (partial)
        '部分来源待补全'
      else if (semester)
        '可导入整学期课表'
      else if (data != null)
        '学校事项来自缓存',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Material(
        color: warn
            ? colors.tertiaryContainer.withValues(alpha: .55)
            : colors.surfaceContainerHighest.withValues(alpha: .6),
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
                  syncOn ? Icons.cloud_done_outlined : Icons.phone_iphone,
                  size: 16,
                  color: warn
                      ? colors.onTertiaryContainer
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: warn
                          ? colors.onTertiaryContainer
                          : colors.onSurfaceVariant,
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

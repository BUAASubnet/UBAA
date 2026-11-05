part of 'view.dart';

extension _AgendaDataSheet on AgendaViewState {
  Future<void> _showDataSheet() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => bound(
      SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('数据与同步', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (available && service.supportsSync) _syncStatusCard(),
              if (result case final data?) ...[
                AgendaCacheStatus(
                  sources: data.sources,
                  route: widget.route,
                  now: agendaTime(now),
                ),
                if (data.schoolCacheFailure != null ||
                    data.sources.any((s) => s.missingScopes.isNotEmpty))
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('部分来源待补全，已有事项仍可查看。'),
                  ),
                if (data.sources.any((s) => s.unprojectableCount > 0))
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('部分学校事项缺少必要字段，未加入时间线。'),
                  ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: available
                          ? () {
                              Navigator.pop(context);
                              unawaited(refreshSchool());
                            }
                          : null,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('刷新学校日程'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: available
                          ? () {
                              Navigator.pop(context);
                              importSchedule();
                            }
                          : null,
                      child: const Text('导入整学期课表'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
    final partial =
        data != null &&
        (data.schoolCacheFailure != null ||
            data.sources.any((s) => s.missingScopes.isNotEmpty));
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

import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/feedback.dart';
import '../../theme.dart' show UbaaTheme;

class AgendaSyncStatusCard extends StatelessWidget {
  const AgendaSyncStatusCard({
    super.key,
    required this.service,
    required this.now,
    required this.boundary,
    required this.isCurrent,
  });
  final AgendaService service;
  final AgendaTime now;
  final Widget Function(Widget) boundary;
  final bool Function() isCurrent;
  Future<void> _run(BuildContext context, AgendaSyncAction action) async {
    if (!isCurrent()) return;
    final AgendaSyncJob job;
    try {
      job = service.prepareSync(action, now);
    } on Object catch (error) {
      final failure = error is AgendaException ? error.failure : null;
      UbaaFeedback.show(context, switch (failure) {
        AgendaFailure.unavailable => '客户端忙，请稍后重试',
        AgendaFailure.superseded => '当前路线不能确认创建，请重新拉取日程',
        _ => '无法准备日程同步，请稍后重试',
      }, kind: UbaaFeedbackKind.warning);
      return;
    }
    if (action == AgendaSyncAction.createConfirmed) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => boundary(
          AlertDialog(
            title: Text(service.syncEnabled ? '创建云端日程' : '启用云端同步'),
            content: const Text(
              '将在个人云盘的 UBAA 日程目录保存自建事项和本机备注、完成与隐藏状态。启用后，打开日程页会拉取云端，修改后自动同步。云端保留历史快照。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(service.syncEnabled ? '确认创建' : '确认启用'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !context.mounted || !isCurrent()) return;
    }
    try {
      await job();
    } on Object {
      /* 服务保留失败状态，供当前账号的状态卡展示。 */
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<AgendaSyncState>(
    stream: service.syncUpdates,
    initialData: service.syncState,
    builder: (context, snapshot) {
      final state = snapshot.data ?? service.syncState;
      final report = state.report;
      final status = report?.status;
      final enable =
          !service.syncEnabled && status != AgendaSyncStatus.outcomeUnknown;
      final count = state.localPendingCount ?? report?.pendingCount ?? 0;
      final mayCreate =
          status == AgendaSyncStatus.needsCreation ||
          status == AgendaSyncStatus.locationUnknown;
      final refreshBeforeCreate =
          (enable || mayCreate) &&
          (state.error != null || status == AgendaSyncStatus.unverified);
      final create = (enable || mayCreate) && !refreshBeforeCreate;
      final text = state.running
          ? '正在同步日程'
          : refreshBeforeCreate
          ? '请重新拉取日程，再确认是否创建'
          : state.error != null
          ? '同步未完成，修改已保存在本机'
          : !service.syncEnabled && status != AgendaSyncStatus.outcomeUnknown
          ? count > 0
                ? '$count 条修改仅保存在本机'
                : '日程仅保存在本机'
          : switch (status) {
              AgendaSyncStatus.upToDate => '日程已同步',
              AgendaSyncStatus.pending => '$count 条修改待同步',
              AgendaSyncStatus.needsCreation => '尚未创建云端日程，$count 条修改保存在本机',
              AgendaSyncStatus.locationUnknown =>
                '尚未找到可确认的云端日程，$count 条修改保存在本机',
              AgendaSyncStatus.unverified => '云端同步暂不可用，$count 条修改保存在本机',
              AgendaSyncStatus.failed => '同步未完成，$count 条修改保存在本机',
              AgendaSyncStatus.conflict => '云端日程已更新，$count 条修改待同步',
              AgendaSyncStatus.outcomeUnknown => '上次云端操作结果待核对，$count 条修改待同步',
              null => service.syncEnabled ? '日程云端同步' : '日程仅保存在本机',
            };
      final reconcile = status == AgendaSyncStatus.outcomeUnknown;
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final ok =
          status == AgendaSyncStatus.upToDate &&
          service.syncEnabled &&
          state.error == null;
      final warn =
          state.error != null ||
          status == AgendaSyncStatus.failed ||
          status == AgendaSyncStatus.conflict ||
          status == AgendaSyncStatus.outcomeUnknown ||
          status == AgendaSyncStatus.unverified;
      final Color tone = ok
          ? UbaaTheme.success(colors)
          : warn
          ? UbaaTheme.warning(colors)
          : service.syncEnabled
          ? colors.primary
          : colors.onSurfaceVariant;
      final IconData icon = state.running
          ? Icons.sync
          : ok
          ? Icons.cloud_done_rounded
          : warn
          ? Icons.cloud_sync_outlined
          : service.syncEnabled
          ? Icons.cloud_upload_outlined
          : Icons.cloud_off_outlined;
      final hint = state.running
          ? '正在与个人云盘交换自建事项'
          : ok
          ? '自建事项与本机标记已保存到个人云盘'
          : enable
          ? '在个人云盘保存自建事项，换设备也能看到'
          : warn
          ? '修改已保存在本机，可稍后重试'
          : '修改后会自动同步，也可立即同步';
      final label = refreshBeforeCreate
          ? '重新拉取'
          : enable
          ? '启用云端同步'
          : create
          ? '创建云端日程'
          : reconcile
          ? '核对云端'
          : '同步';
      final onPressed =
          state.running ||
              status == AgendaSyncStatus.unverified && !refreshBeforeCreate
          ? null
          : () => _run(
              context,
              create
                  ? AgendaSyncAction.createConfirmed
                  : reconcile || refreshBeforeCreate
                  ? AgendaSyncAction.pull
                  : AgendaSyncAction.push,
            );
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            tone.withValues(alpha: .08),
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
                color: tone.withValues(alpha: .15),
                shape: BoxShape.circle,
              ),
              child: state.running
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: tone,
                      ),
                    )
                  : Icon(icon, color: tone, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            enable || create
                ? FilledButton(onPressed: onPressed, child: Text(label))
                : FilledButton.tonal(onPressed: onPressed, child: Text(label)),
          ],
        ),
      );
    },
  );
}

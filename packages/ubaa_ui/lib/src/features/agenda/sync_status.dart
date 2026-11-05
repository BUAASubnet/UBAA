import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/feedback.dart';

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
        AgendaFailure.unavailable => '客户端忙，请稍后再试',
        AgendaFailure.superseded => '当前路线不能确认创建，请重新拉取日程',
        _ => '无法准备日程同步，请稍后再试',
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
      final refreshBeforeCreate = mayCreate && state.error != null;
      final create = enable || mayCreate && !refreshBeforeCreate;
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
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  state.running
                      ? Icons.sync
                      : status == AgendaSyncStatus.upToDate
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_queue,
                ),
                Text(text),
                TextButton(
                  onPressed:
                      state.running || status == AgendaSyncStatus.unverified
                      ? null
                      : () => _run(
                          context,
                          create
                              ? AgendaSyncAction.createConfirmed
                              : reconcile || refreshBeforeCreate
                              ? AgendaSyncAction.pull
                              : AgendaSyncAction.push,
                        ),
                  child: Text(
                    enable
                        ? '启用云端同步'
                        : create
                        ? '创建云端日程'
                        : refreshBeforeCreate
                        ? '重新拉取'
                        : reconcile
                        ? '核对云端'
                        : '同步',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

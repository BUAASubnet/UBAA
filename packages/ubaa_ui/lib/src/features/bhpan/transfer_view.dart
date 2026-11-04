import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'format.dart';

class BhpanProgressTile extends StatelessWidget {
  const BhpanProgressTile({required this.progress, this.onCancel, super.key});
  final BhpanTransferProgress progress;
  final VoidCallback? onCancel;
  @override
  Widget build(BuildContext context) {
    final active = !const {
      BhpanTransferPhase.completed,
      BhpanTransferPhase.cancelled,
      BhpanTransferPhase.failed,
      BhpanTransferPhase.outcomeUnknown,
      BhpanTransferPhase.blocked,
    }.contains(progress.phase);
    return ListTile(
      leading: const Icon(Icons.swap_vert),
      title: Text(switch (progress.phase) {
        BhpanTransferPhase.queued => '排队',
        BhpanTransferPhase.hashingMini => '计算秒传检查摘要',
        BhpanTransferPhase.hashingFull => '计算完整文件摘要',
        BhpanTransferPhase.checking => '检查秒传',
        BhpanTransferPhase.awaitingConfirmation => '等待上传确认',
        BhpanTransferPhase.submitting => '正在提交',
        BhpanTransferPhase.completed => '传输完成',
        BhpanTransferPhase.cancelled => '任务已取消',
        BhpanTransferPhase.failed => '任务失败',
        BhpanTransferPhase.outcomeUnknown => '上传结果待核对',
        BhpanTransferPhase.blocked => '文件不支持秒传',
        BhpanTransferPhase.uploading => '正在上传',
        BhpanTransferPhase.downloading => '正在下载',
        BhpanTransferPhase.finalizing => '正在完成登记',
      }),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${bhpanBytes(progress.bytes)} / ${bhpanBytes(progress.total)}'),
          if (active)
            LinearProgressIndicator(
              value: progress.total > 0
                  ? (progress.bytes / progress.total).clamp(0.0, 1.0)
                  : null,
            ),
        ],
      ),
      trailing: TextButton(
        onPressed: active ? onCancel : null,
        child: const Text('取消任务'),
      ),
    );
  }
}

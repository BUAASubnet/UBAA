import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'format.dart';

const _finished = {
  BhpanTransferPhase.completed,
  BhpanTransferPhase.cancelled,
  BhpanTransferPhase.failed,
  BhpanTransferPhase.outcomeUnknown,
  BhpanTransferPhase.blocked,
};

bool bhpanTransferActive(BhpanTransferPhase phase) =>
    !_finished.contains(phase);

String bhpanPhaseText(BhpanTransferPhase phase) => switch (phase) {
  BhpanTransferPhase.queued => '准备中',
  BhpanTransferPhase.hashingMini || BhpanTransferPhase.checking => '正在检查能否秒传',
  BhpanTransferPhase.hashingFull => '正在校验文件',
  BhpanTransferPhase.awaitingConfirmation => '等待确认',
  BhpanTransferPhase.submitting => '正在提交',
  BhpanTransferPhase.uploading => '正在上传',
  BhpanTransferPhase.downloading => '正在下载',
  BhpanTransferPhase.finalizing => '正在完成',
  BhpanTransferPhase.completed => '已完成',
  BhpanTransferPhase.cancelled => '已取消',
  BhpanTransferPhase.failed => '没有完成',
  BhpanTransferPhase.outcomeUnknown => '结果未确认，请刷新查看后再决定是否重试',
  BhpanTransferPhase.blocked => '云端没有相同文件，改为普通上传',
};

/// 列表上方的传输卡片：文件名、阶段、进度；进行中可取消，结束后可关闭。
class BhpanProgressTile extends StatelessWidget {
  const BhpanProgressTile({
    required this.progress,
    this.label,
    this.upload = true,
    this.onCancel,
    this.onClose,
    super.key,
  });
  final BhpanTransferProgress progress;
  final String? label;
  final bool upload;
  final VoidCallback? onCancel, onClose;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final phase = progress.phase;
    final active = bhpanTransferActive(phase);
    final ratio = progress.total > 0
        ? (progress.bytes / progress.total).clamp(0.0, 1.0)
        : null;
    final moving =
        phase == BhpanTransferPhase.uploading ||
        phase == BhpanTransferPhase.downloading;
    final detail = [
      bhpanPhaseText(phase),
      if (moving && ratio != null) '${(ratio * 100).round()}%',
      if (moving && progress.total > 0)
        '${bhpanBytes(progress.bytes)} / ${bhpanBytes(progress.total)}',
    ].join(' · ');
    final (icon, tint) = switch (phase) {
      BhpanTransferPhase.completed => (Icons.check_circle, colors.primary),
      BhpanTransferPhase.failed => (Icons.error_outline, colors.error),
      BhpanTransferPhase.outcomeUnknown => (
        Icons.help_outline,
        colors.tertiary,
      ),
      BhpanTransferPhase.cancelled => (Icons.cancel_outlined, colors.outline),
      _ => (
        upload ? Icons.upload_rounded : Icons.download_rounded,
        colors.primary,
      ),
    };
    return Card(
      key: const ValueKey('bhpan-transfer'),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      color: colors.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label ?? (upload ? '上传文件' : '下载文件'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 2,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (active) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: moving ? ratio : null,
                        minHeight: 4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: active ? '取消任务' : '关闭',
              onPressed: active ? onCancel : onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

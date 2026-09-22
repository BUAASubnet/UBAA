part of '../../widgets.dart';

class _ScheduleImportBar extends StatelessWidget {
  const _ScheduleImportBar({
    required this.term,
    required this.state,
    required this.onSave,
    this.onCancel,
  });
  final String term;
  final ScheduleImportState? state;
  final Future<void> Function(String) onSave;
  final ValueChanged<String>? onCancel;

  Future<void> _save(BuildContext context) async {
    try {
      await onSave(term);
    } on Object {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时无法开始保存，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = state?.status;
    final running = status == ScheduleImportStatus.running;
    final progress = state?.progress;
    final text = switch (status) {
      ScheduleImportStatus.running =>
        progress?.totalWeeks == null
            ? '正在准备整学期课表'
            : '正在保存：${progress!.completedWeeks} / ${progress.totalWeeks} 周',
      ScheduleImportStatus.saved => '整学期已保存，可离线查看',
      ScheduleImportStatus.cancelled => '已取消保存',
      ScheduleImportStatus.failed =>
        progress?.saveFailure == CacheMaintenanceFailure.capacity
            ? '本机空间不足，整学期未保存'
            : progress?.saveFailure != null
            ? '课表已读取，但未能保存到本机'
            : state?.error?.title ?? '整学期未保存，请重试',
      null => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          if (text != null) Text(text),
          if (running)
            TextButton(
              onPressed: onCancel == null ? null : () => onCancel!(term),
              child: const Text('取消保存'),
            )
          else
            TextButton.icon(
              onPressed: () => _save(context),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(
                status == ScheduleImportStatus.failed ||
                        status == ScheduleImportStatus.saved
                    ? '重新保存'
                    : '保存整学期',
              ),
            ),
        ],
      ),
    );
  }
}

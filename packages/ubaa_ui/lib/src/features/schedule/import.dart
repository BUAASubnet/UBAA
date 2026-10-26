import '../../shared/feedback.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 正常同步不占用课表空间，仅在失败时提供恢复入口。
class ScheduleRefreshError extends StatelessWidget {
  const ScheduleRefreshError({
    required this.term,
    required this.state,
    required this.onRefresh,
  });
  final String term;
  final ScheduleImportState? state;
  final Future<void> Function(String) onRefresh;

  Future<void> _retry(BuildContext context) async {
    try {
      await onRefresh(term);
    } on Object {
      if (context.mounted) {
        UbaaFeedback.show(context, '刷新失败，请稍后重试', kind: UbaaFeedbackKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (state?.status != ScheduleImportStatus.failed) {
      return const SizedBox.shrink();
    }
    final message =
        state?.progress?.saveFailure == CacheMaintenanceFailure.capacity
        ? '设备空间不足，请清理后重试'
        : '课表刷新失败，请重试';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Text(message),
          TextButton(onPressed: () => _retry(context), child: const Text('重试')),
        ],
      ),
    );
  }
}

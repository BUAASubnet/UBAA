part of '../../widgets.dart';

class _GradeScoreBanner extends StatelessWidget {
  const _GradeScoreBanner({required this.notice, this.onOpen, this.onDismiss});
  final GradeScoreNotice notice;
  final VoidCallback? onOpen, onDismiss;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    final title = notice.changes.length == 1
        ? '${notice.changes.single.courseName} 成绩已更新'
        : '${notice.termName} 有 ${notice.changes.length} 门成绩更新';
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '前往成绩查询查看最新分数',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onPrimaryContainer,
          ),
        ),
      ],
    );
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(onPressed: onOpen, child: const Text('查看')),
        TextButton(onPressed: onDismiss, child: const Text('忽略')),
      ],
    );
    return Material(
      key: const ValueKey('home-grade-update'),
      color: colors.primaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(14) > 16.8
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    text,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: buttons),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 12),
                    buttons,
                  ],
                ),
        ),
      ),
    );
  }
}

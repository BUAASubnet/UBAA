part of '../../widgets.dart';

class _YgdkSummary extends StatelessWidget {
  const _YgdkSummary(this.overview);
  final YgdkOverview overview;
  @override
  Widget build(BuildContext context) {
    final p = overview;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (p.termTarget ?? 0) > 0
              ? '本学期认定次数 ${p.termCount} / ${p.termTarget}'
              : '本学期认定次数 ${p.termCount} 次',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (p.weekCount != null) ...[
          const SizedBox(height: 8),
          Text(
            p.weekTarget == null
                ? '本周打卡 ${p.weekCount} 次'
                : '本周打卡 ${p.weekCount} / ${p.weekTarget}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

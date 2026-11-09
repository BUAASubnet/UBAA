import 'package:flutter/material.dart';
import '../../theme.dart' show UbaaTheme;
import 'package:ubaa_domain/ubaa_domain.dart';

class YgdkSummary extends StatelessWidget {
  const YgdkSummary(this.overview, {this.statisticsKnown = true});
  final bool statisticsKnown;
  final YgdkOverview overview;
  @override
  Widget build(BuildContext context) {
    final p = overview;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          !statisticsKnown
              ? '本学期认定次数 --'
              : (p.termTarget ?? 0) > 0
              ? '本学期认定次数 ${p.termCount} / ${p.termTarget}'
              : '本学期认定次数 ${p.termCount} 次',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        // 有学期目标时用进度条直观显示完成度，达标后改用成功色。
        if (statisticsKnown && (p.termTarget ?? 0) > 0) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: (p.termCount / p.termTarget!).clamp(0, 1).toDouble(),
            minHeight: 6,
            borderRadius: BorderRadius.circular(4),
            color: p.termCount >= p.termTarget!
                ? UbaaTheme.success(theme.colorScheme)
                : null,
          ),
        ],
        if (statisticsKnown && p.weekCount != null) ...[
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

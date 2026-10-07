import 'package:flutter/material.dart';
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
              ? '统计尚未确认'
              : (p.termTarget ?? 0) > 0
              ? '本学期认定次数 ${p.termCount} / ${p.termTarget}'
              : '本学期认定次数 ${p.termCount} 次',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
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

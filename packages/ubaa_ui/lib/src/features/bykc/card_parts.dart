import 'package:flutter/material.dart';

class BykcCardTags extends StatelessWidget {
  const BykcCardTags({
    this.category,
    this.campuses = const [],
    this.selfSign = false,
  });
  final String? category;
  final List<String> campuses;
  final bool selfSign;

  @override
  Widget build(BuildContext context) {
    final labels = [
      if (category?.trim().isNotEmpty == true) category!,
      // “未指定校区”没有信息量，地点里通常已写明校区。
      ...campuses.where(
        (value) => value.trim().isNotEmpty && value.trim() != '未指定校区',
      ),
    ];
    if (labels.isEmpty && !selfSign) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final label in labels) _Tag(label),
          if (selfSign) const _Tag('自主签到', icon: Icons.location_on_outlined),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = icon == null ? colors.onSurfaceVariant : colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: icon == null
            ? colors.surfaceContainerHighest
            : colors.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// 教师与地点合为一行，时间一行，选课/退选时间一行。
class BykcCardInfo extends StatelessWidget {
  const BykcCardInfo({
    this.teacher,
    this.position,
    this.time,
    this.deadlineLabel,
    this.deadline,
  });
  final String? teacher, position, time, deadlineLabel, deadline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    String? clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    final people = [?clean(teacher), ?clean(position)].join(' · ');
    final until = clean(deadline);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (clean(time) case final t?)
            Text(t, style: theme.textTheme.bodyMedium),
          if (people.isNotEmpty)
            Text(
              people,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          if (until != null)
            Text([?deadlineLabel, until].join(' '), style: muted),
        ],
      ),
    );
  }
}

class BykcCardFooter extends StatelessWidget {
  const BykcCardFooter({required this.summary, this.action});
  final Widget summary;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (action != null &&
            constraints.maxWidth < 360 &&
            MediaQuery.textScalerOf(context).scale(14) > 22) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              summary,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: action),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: summary),
            if (action != null) ...[const SizedBox(width: 16), action!],
          ],
        );
      },
    ),
  );
}

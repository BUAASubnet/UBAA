import 'package:flutter/material.dart';
import 'display.dart' show BykcInfoLine;

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
      ...campuses.where((value) => value.trim().isNotEmpty),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final people = [
          BykcInfoLine('教师', teacher, maxLines: 1),
          BykcInfoLine('地点', position, maxLines: 1),
        ];
        final schedule = [
          BykcInfoLine('时间', time),
          if (deadlineLabel != null) BykcInfoLine(deadlineLabel!, deadline),
        ];
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final hasPeople = [
          teacher,
          position,
        ].any((value) => value?.trim().isNotEmpty == true);
        final hasSchedule = [
          time,
          deadline,
        ].any((value) => value?.trim().isNotEmpty == true);
        if (constraints.maxWidth >= 560 * scale && hasPeople && hasSchedule) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: people,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: schedule,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [...people, ...schedule],
        );
      },
    ),
  );
}

class BykcCardFooter extends StatelessWidget {
  const BykcCardFooter({required this.summary, this.action});
  final Widget summary;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
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

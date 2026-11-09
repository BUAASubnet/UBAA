import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'calendar_values.dart';
import 'format.dart';

class AgendaMonthCalendar extends StatelessWidget {
  const AgendaMonthCalendar({
    super.key,
    required this.date,
    required this.entries,
    required this.onSelected,
    this.today,
    this.colorOf,
  });
  final DateTime date;
  final DateTime? today;
  final List<AgendaEntry> entries;
  final ValueChanged<DateTime> onSelected;
  final Color Function(AgendaEntry)? colorOf;
  @override
  Widget build(BuildContext context) {
    final first = agendaWeekStart(DateTime.utc(date.year, date.month));
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Row(
              children: [
                for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          GridView.builder(
            key: const ValueKey('agenda-month-calendar'),
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: math.max(48, 44 * scale),
            ),
            itemCount:
                7 *
                ((DateTime.utc(date.year, date.month).difference(first).inDays +
                        DateUtils.getDaysInMonth(date.year, date.month) +
                        6) ~/
                    7),
            itemBuilder: (context, index) {
              final day = first.add(Duration(days: index));
              final dayEntries = entries
                  .where((e) => agendaOnDay(e, day))
                  .toList();
              final count = dayEntries.length;
              final selected = day == agendaDay(date);
              final isToday = today != null && agendaDay(today!) == day;
              final colors = Theme.of(context).colorScheme;
              return Semantics(
                label: '${agendaDate(day)}，$count项',
                selected: selected,
                button: true,
                child: InkWell(
                  key: ValueKey('agenda-day-${agendaDate(day)}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelected(day),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: selected ? colors.primaryContainer : null,
                      border: isToday && !selected
                          ? Border.all(color: colors.primary, width: 1.5)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${day.day}',
                            maxLines: 1,
                            style: TextStyle(
                              color: isToday
                                  ? colors.primary
                                  : selected
                                  ? colors.onPrimaryContainer
                                  : day.month == date.month
                                  ? colors.onSurface
                                  : colors.outlineVariant,
                              fontWeight: selected || isToday
                                  ? FontWeight.w500
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        SizedBox(
                          height: 5,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final e in dayEntries.take(3))
                                Container(
                                  width: 5,
                                  height: 5,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: colorOf?.call(e) ?? colors.primary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class AgendaDateStrip extends StatelessWidget {
  const AgendaDateStrip({
    super.key,
    required this.date,
    required this.entries,
    required this.onSelected,
    this.today,
    this.onSwipe,
    this.colorOf,
  });
  final DateTime date;
  final DateTime? today;
  final List<AgendaEntry> entries;
  final ValueChanged<DateTime> onSelected;
  final ValueChanged<int>? onSwipe;
  final Color Function(AgendaEntry)? colorOf;
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final monday = agendaWeekStart(date);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: onSwipe == null
          ? null
          : (details) {
              final v = details.primaryVelocity ?? 0;
              if (v.abs() > 200) onSwipe!(v < 0 ? 1 : -1);
            },
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Builder(
                builder: (context) {
                  final day = monday.add(Duration(days: i));
                  final selected = agendaDay(date) == day;
                  final isToday = today != null && agendaDay(today!) == day;
                  final dayEntries = entries
                      .where((e) => agendaOnDay(e, day))
                      .take(3)
                      .toList();
                  final weekend = i >= 5;
                  // 日期圆随字号放大，但不超过一周七格的宽度。
                  final circleSize = MediaQuery.textScalerOf(
                    context,
                  ).scale(36).clamp(36.0, 50.0);
                  final Color circle = isToday
                      ? colors.primary
                      : selected
                      ? colors.primaryContainer
                      : Colors.transparent;
                  final Color number = isToday
                      ? colors.onPrimary
                      : selected
                      ? colors.onPrimaryContainer
                      : weekend
                      ? colors.onSurfaceVariant
                      : colors.onSurface;
                  return Semantics(
                    button: true,
                    selected: selected,
                    label:
                        '周${_weekdays[i]} ${day.month}月${day.day}日${dayEntries.isEmpty ? '' : '，有事项'}',
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onSelected(day),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _weekdays[i],
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isToday
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                                fontWeight: isToday
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 6),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: circleSize,
                              height: circleSize,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: circle,
                                shape: BoxShape.circle,
                                border: selected && isToday
                                    ? Border.all(
                                        color: colors.primaryContainer,
                                        width: 3,
                                      )
                                    : null,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${day.day}',
                                  maxLines: 1,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: number,
                                    fontWeight: isToday || selected
                                        ? FontWeight.w500
                                        : FontWeight.w400,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            SizedBox(
                              height: 5,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (final e in dayEntries)
                                    Container(
                                      width: 5,
                                      height: 5,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color:
                                            colorOf?.call(e) ?? colors.primary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

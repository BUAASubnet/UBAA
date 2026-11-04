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
  });
  final DateTime date;
  final List<AgendaEntry> entries;
  final ValueChanged<DateTime> onSelected;
  @override
  Widget build(BuildContext context) {
    final first = agendaWeekStart(DateTime.utc(date.year, date.month));
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '${date.year}年${date.month}月',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Row(
            children: [
              for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(child: Center(child: Text(label))),
            ],
          ),
          GridView.builder(
            key: const ValueKey('agenda-month-calendar'),
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: math.max(48, 44 * scale),
            ),
            itemCount: 42,
            itemBuilder: (context, index) {
              final day = first.add(Duration(days: index));
              final count = entries.where((e) => agendaOnDay(e, day)).length;
              final selected = day == agendaDay(date);
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
                              color: selected
                                  ? colors.onPrimaryContainer
                                  : day.month == date.month
                                  ? colors.onSurface
                                  : colors.onSurfaceVariant,
                              fontWeight: selected ? FontWeight.bold : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        SizedBox(
                          height: 5,
                          child: count == 0
                              ? null
                              : Container(
                                  width: 5,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: selected
                                        ? colors.onPrimaryContainer
                                        : colors.primary,
                                  ),
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
  });
  final DateTime date;
  final List<AgendaEntry> entries;
  final ValueChanged<DateTime> onSelected;
  @override
  Widget build(BuildContext context) {
    final monday = agendaWeekStart(date);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Builder(
              builder: (context) {
                final day = monday.add(Duration(days: i));
                final selected = agendaDay(date) == day;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ChoiceChip(
                    label: Text(
                      '${['一', '二', '三', '四', '五', '六', '日'][i]}\n${day.month}/${day.day}${entries.any((e) => agendaOnDay(e, day)) ? ' ·' : ''}',
                    ),
                    selected: selected,
                    onSelected: (_) => onSelected(day),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

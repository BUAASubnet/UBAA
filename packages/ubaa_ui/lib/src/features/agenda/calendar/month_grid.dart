import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../calendar_values.dart';
import 'entry_chip.dart';
import '../format.dart';

/// 宽屏月视图：整月网格，格子里直接列出当天事项，放不下的收成「+N」。
///
/// 窄屏仍用 [AgendaMonthCalendar] 加当天列表；宽屏左栏已有小月历，主区改看整月安排。
class AgendaMonthGrid extends StatelessWidget {
  const AgendaMonthGrid({
    super.key,
    required this.date,
    required this.today,
    required this.entries,
    required this.allEntries,
    required this.onSelected,
    required this.onOpen,
  });
  final DateTime date, today;
  final List<AgendaEntry> entries, allEntries;
  final ValueChanged<DateTime> onSelected;
  final ValueChanged<AgendaEntry> onOpen;
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  static const _chipHeight = 21.0;

  /// 格子够宽时在标题前加时刻；窄格只放标题。
  String _label(AgendaEntry entry, {required bool timed}) {
    final title = agendaTitle(entry);
    if (!timed) return title;
    final start = switch (entry.timing.kind) {
      AgendaTimingKind.deadline => agendaValue(entry.timing.due),
      AgendaTimingKind.period => agendaValue(entry.timing.start),
      AgendaTimingKind.allDay || AgendaTimingKind.undated => null,
    };
    return start == null ? title : '${agendaHm(start)} $title';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final month = DateTime.utc(date.year, date.month);
    final first = agendaWeekStart(month);
    final weeks =
        (month.difference(first).inDays +
            DateUtils.getDaysInMonth(date.year, date.month) +
            6) ~/
        7;
    final line = BorderSide(color: colors.outlineVariant.withValues(alpha: .6));
    final selectedDay = agendaDay(date), todayDay = agendaDay(today);
    return Column(
      key: const ValueKey('agenda-month-grid'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    _weekdays[i],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: line, left: line),
            ),
            child: Column(
              children: [
                for (var w = 0; w < weeks; w++)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var d = 0; d < 7; d++)
                          Expanded(
                            child: _cell(
                              context,
                              first.add(Duration(days: w * 7 + d)),
                              line: line,
                              selected: selectedDay,
                              today: todayDay,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    DateTime day, {
    required BorderSide line,
    required DateTime selected,
    required DateTime today,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final inMonth = day.month == date.month;
    final isToday = day == today, isSelected = day == selected;
    // 与列表一致：连续小节合并为一门课，签到并入对应课程。
    final items = [
      for (final (entry, _, _) in agendaAttachSignins(
        agendaMergeCourses(
          entries.where((e) => agendaOnDay(e, day)).toList()..sort(
            (a, b) => (agendaEntryDate(a) ?? day).compareTo(
              agendaEntryDate(b) ?? day,
            ),
          ),
        ),
      ))
        entry,
    ];
    final title = agendaMonthDayWeek(day);
    return Semantics(
      label: '$title，${items.length}项',
      selected: isSelected,
      child: Material(
        color: isSelected
            ? colors.primaryContainer.withValues(alpha: .35)
            : inMonth
            ? Colors.transparent
            : colors.onSurface.withValues(alpha: .025),
        shape: Border(right: line, bottom: line),
        child: InkWell(
          key: ValueKey('agenda-month-cell-${agendaDate(day)}'),
          onTap: () => onSelected(day),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 日期行之外能放几条就放几条；放不下时最后一格让给「+N」。
              final room = ((constraints.maxHeight - 30) / _chipHeight)
                  .floor()
                  .clamp(0, 99);
              final shown = items.length <= room
                  ? items.length
                  : (room - 1).clamp(0, items.length);
              final hidden = items.length - shown;
              return Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: isToday
                            ? BoxDecoration(
                                color: colors.primary,
                                shape: BoxShape.circle,
                              )
                            : null,
                        child: Text(
                          '${day.day}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: isToday || isSelected
                                ? FontWeight.w500
                                : FontWeight.w400,
                            color: isToday
                                ? colors.onPrimary
                                : inMonth
                                ? colors.onSurface
                                : colors.outline,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    for (final entry in items.take(shown))
                      SizedBox(
                        height: _chipHeight,
                        child: AgendaEntryChip(
                          entry: entry,
                          label: _label(
                            entry,
                            timed: constraints.maxWidth >= 120,
                          ),
                          conflict: agendaEntryConflicts(
                            entry,
                            allEntries,
                          ).isNotEmpty,
                          onTap: () => onOpen(entry),
                        ),
                      ),
                    if (hidden > 0)
                      SizedBox(
                        height: _chipHeight,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => showAgendaEntryList(
                            context,
                            title: title,
                            entries: items,
                            onOpen: onOpen,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Text(
                                '还有 $hidden 项',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

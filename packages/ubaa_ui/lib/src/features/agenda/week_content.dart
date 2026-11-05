import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/layout/seven_day_grid.dart';
import 'calendar_values.dart';
import 'format.dart';

typedef _Slot = ({
  AgendaEntry entry,
  DateTime start,
  DateTime end,
  DateTime displayEnd,
});

class AgendaWeekContent extends StatefulWidget {
  const AgendaWeekContent({
    super.key,
    required this.date,
    required this.entries,
    required this.allEntries,
    required this.onOpen,
    required this.onDate,
  });
  final DateTime date;
  final List<AgendaEntry> entries, allEntries;
  final ValueChanged<AgendaEntry> onOpen;
  final ValueChanged<DateTime> onDate;
  @override
  State<AgendaWeekContent> createState() => _AgendaWeekContentState();
}

class _AgendaWeekContentState extends State<AgendaWeekContent> {
  final horizontal = ScrollController(), vertical = ScrollController();
  bool positioned = false;
  bool focusPositioned = false;
  double? lastViewport, lastColumn;
  @override
  void dispose() {
    horizontal.dispose();
    vertical.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AgendaWeekContent old) {
    super.didUpdateWidget(old);
    if (agendaWeekStart(old.date) != agendaWeekStart(widget.date))
      positioned = false;
    if (agendaDay(old.date) != agendaDay(widget.date)) focusPositioned = false;
  }

  Widget block(AgendaEntry entry) {
    final colors = Theme.of(context).colorScheme;
    final conflict = agendaEntryConflicts(entry, widget.allEntries).isNotEmpty;
    final color =
        agendaColor(entry.local?.content.color) ??
        (entry.school?.navigation.feature == AgendaFeature.schedule
            ? colors.tertiaryContainer
            : colors.secondaryContainer);
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Tooltip(
        message:
            '${agendaTitle(entry)} · ${agendaWhen(entry)}${conflict ? ' · 与课程重叠' : ''}',
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(5),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => widget.onOpen(entry),
            child: Builder(
              builder: (context) {
                final fg =
                    ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black87;
                final place =
                    entry.local?.content.location ?? entry.school?.location;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(3, 3, 2, 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          agendaTitle(entry),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                      ),
                      if (place?.isNotEmpty == true)
                        Flexible(
                          child: Text(
                            '@$place',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9.5,
                              height: 1.2,
                              color: fg.withValues(alpha: .85),
                            ),
                          ),
                        ),
                      if (conflict)
                        Icon(Icons.event_busy_outlined, size: 12, color: fg),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> blocks(
    DateTime monday,
    double column,
    double axis,
    double hourHeight,
  ) {
    final widgets = <Widget>[];
    for (var i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i)),
          tomorrow = monday.add(Duration(days: i + 1));
      final slots = <_Slot>[];
      for (final entry in widget.entries) {
        if (entry.timing.kind != AgendaTimingKind.period ||
            !agendaOnDay(entry, day))
          continue;
        final rawStart = agendaStart(entry), rawEnd = agendaEnd(entry);
        if (rawStart == null || rawEnd == null || !rawEnd.isAfter(rawStart))
          continue;
        final start = rawStart.isBefore(day) ? day : rawStart;
        final end = rawEnd.isAfter(tomorrow) ? tomorrow : rawEnd;
        final minimum = start.add(const Duration(minutes: 30));
        slots.add((
          entry: entry,
          start: start,
          end: end,
          displayEnd: minimum.isAfter(end) ? minimum : end,
        ));
      }
      slots.sort((a, b) => a.start.compareTo(b.start));
      for (var k = slots.length - 1; k > 0; k--) {
        final prev = slots[k - 1], next = slots[k];
        if (!agendaCourseContinues(
          prev.entry,
          prev.end,
          next.entry,
          next.start,
        ))
          continue;
        final minimum = prev.start.add(const Duration(minutes: 30));
        slots[k - 1] = (
          entry: prev.entry,
          start: prev.start,
          end: next.end,
          displayEnd: minimum.isAfter(next.end) ? minimum : next.end,
        );
        slots.removeAt(k);
      }
      var cursor = 0;
      while (cursor < slots.length) {
        final group = <_Slot>[slots[cursor++]];
        var last = group.first.displayEnd;
        while (cursor < slots.length && slots[cursor].start.isBefore(last)) {
          final slot = slots[cursor++];
          group.add(slot);
          if (slot.displayEnd.isAfter(last)) last = slot.displayEnd;
        }
        final ends = <DateTime>[];
        final lanes = <int>[];
        for (final slot in group) {
          var lane = ends.indexWhere((end) => !end.isAfter(slot.start));
          if (lane < 0) {
            lane = ends.length;
            ends.add(slot.displayEnd);
          } else {
            ends[lane] = slot.displayEnd;
          }
          lanes.add(lane);
        }
        for (var j = 0; j < group.length; j++) {
          final slot = group[j];
          final top = math.min(
            slot.start.difference(day).inSeconds / 3600 * hourHeight,
            23.5 * hourHeight,
          );
          widgets.add(
            Positioned(
              key: ValueKey('agenda-week-${agendaEntryKey(slot.entry)}-$i'),
              left: axis + i * column + lanes[j] * column / ends.length,
              top: top,
              width: column / ends.length,
              height: math.max(
                hourHeight / 2,
                slot.end.difference(slot.start).inSeconds / 3600 * hourHeight,
              ),
              child: block(slot.entry),
            ),
          );
        }
      }
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      final axis = 40 * scale, hourHeight = 56 * scale;
      final width = constraints.maxWidth;
      final column = (width - axis) / 7;
      if (lastViewport != constraints.maxWidth || lastColumn != column) {
        focusPositioned = false;
        if (lastColumn != column) positioned = false;
        lastViewport = constraints.maxWidth;
        lastColumn = column;
      }
      final monday = agendaWeekStart(widget.date);
      if (!focusPositioned) {
        focusPositioned = true;
        final focus = agendaDay(widget.date).difference(monday).inDays;
        final offset =
            focus * column - (constraints.maxWidth - axis - column) / 2;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && horizontal.hasClients)
            horizontal.jumpTo(
              offset.clamp(0, horizontal.position.maxScrollExtent).toDouble(),
            );
        });
      }
      final top = widget.entries
          .where(
            (e) =>
                e.timing.kind != AgendaTimingKind.period ||
                agendaStart(e) == null ||
                agendaEnd(e) == null,
          )
          .toList();
      if (!positioned) {
        positioned = true;
        var firstHour = 7;
        final times = widget.entries
            .where((e) => e.timing.kind == AgendaTimingKind.period)
            .map(agendaStart)
            .whereType<DateTime>()
            .toList();
        if (times.isNotEmpty)
          firstHour = times.map((t) => t.hour).reduce(math.min);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && vertical.hasClients)
            vertical.jumpTo(
              math.min(
                firstHour * hourHeight,
                vertical.position.maxScrollExtent,
              ),
            );
        });
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (top.isNotEmpty) ...[
            const Text('全天、截止与时间待确认'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in top)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(
                          '${agendaEntryDate(entry) == null ? '无日期' : agendaDate(agendaEntryDate(entry)!).substring(5)} ${agendaWhen(entry)} · ${agendaTitle(entry)}${agendaEntryConflicts(entry, widget.allEntries).isEmpty ? '' : ' · 与课程重叠'}',
                        ),
                        onPressed: () => widget.onOpen(entry),
                      ),
                    ),
                ],
              ),
            ),
          ],
          Expanded(
            child: Scrollbar(
              controller: horizontal,
              thumbVisibility: width > constraints.maxWidth,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: horizontal,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(width: axis),
                          for (var i = 0; i < 7; i++)
                            SizedBox(
                              width: column,
                              child: _WeekHeaderDay(
                                day: monday.add(Duration(days: i)),
                                index: i,
                                selected:
                                    agendaDay(widget.date) ==
                                    monday.add(Duration(days: i)),
                                today:
                                    agendaDay(campusToday()) ==
                                    monday.add(Duration(days: i)),
                                onTap: () => widget.onDate(
                                  monday.add(Duration(days: i)),
                                ),
                              ),
                            ),
                        ],
                      ),
                      Expanded(
                        child: ListView(
                          controller: vertical,
                          key: const ValueKey('agenda-week-grid'),
                          children: [
                            SevenDayTimeGrid(
                              rows: 24,
                              rowHeight: hourHeight,
                              axisWidth: axis,
                              today: agendaDay(
                                widget.date,
                              ).difference(monday).inDays,
                              axis: PinnedWeekAxis(
                                controller: horizontal,
                                width: axis,
                                child: Column(
                                  children: [
                                    for (var hour = 0; hour < 24; hour++)
                                      SizedBox(
                                        height: hourHeight,
                                        child: Align(
                                          alignment: Alignment.topCenter,
                                          child: Text(
                                            '${hour.toString().padLeft(2, '0')}:00',
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              children: blocks(
                                monday,
                                column,
                                axis,
                                hourHeight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

DateTime campusToday() => agendaDay(campusDate(DateTime.now()));

class _WeekHeaderDay extends StatelessWidget {
  const _WeekHeaderDay({
    required this.day,
    required this.index,
    required this.selected,
    required this.today,
    required this.onTap,
  });
  final DateTime day;
  final int index;
  final bool selected, today;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '周${['一', '二', '三', '四', '五', '六', '日'][index]} ${day.month}月${day.day}日',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ['一', '二', '三', '四', '五', '六', '日'][index],
                style: theme.textTheme.labelSmall?.copyWith(
                  color: today ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: today
                      ? colors.primary
                      : selected
                      ? colors.primaryContainer
                      : null,
                ),
                child: Text(
                  '${day.day}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: today
                        ? colors.onPrimary
                        : selected
                        ? colors.onPrimaryContainer
                        : colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

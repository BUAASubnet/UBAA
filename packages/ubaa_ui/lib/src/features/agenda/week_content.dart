import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/seven_day_grid.dart';
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
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => widget.onOpen(entry),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      agendaTitle(entry),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            ThemeData.estimateBrightnessForColor(color) ==
                                Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                  ),
                  if (conflict) const Icon(Icons.event_busy_outlined, size: 14),
                ],
              ),
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
      final width = math.max(
        constraints.maxWidth,
        7 * 112 * scale + 54 * scale,
      );
      final axis = 54 * scale, hourHeight = 64 * scale;
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
                              child: TextButton(
                                onPressed: () => widget.onDate(
                                  monday.add(Duration(days: i)),
                                ),
                                child: Text(
                                  '周${['一', '二', '三', '四', '五', '六', '日'][i]}\n${monday.add(Duration(days: i)).month}/${monday.add(Duration(days: i)).day}',
                                  textAlign: TextAlign.center,
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

import 'package:clock/clock.dart' show clock;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'calendar/entry_chip.dart';
import '../../shared/layout/seven_day_grid.dart';
import 'calendar_values.dart';
import 'format.dart';
import 'list_content.dart' show agendaSourceColor;

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
  bool focusPositioned = false;
  double? lastViewport, lastColumn;

  /// 默认显示 08:00–23:00，超出范围的事项向两端扩展。
  int firstHour = 8, lastHour = 23;

  /// 本周最早开始的事项距网格顶部的小时数；跨午夜后半段把范围拉大时用于首屏定位。
  double? earliestStart;
  bool positioned = false;
  @override
  void dispose() {
    horizontal.dispose();
    vertical.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AgendaWeekContent old) {
    super.didUpdateWidget(old);
    // 换周后网格范围会变，回到顶部从最早事项看起。
    if (agendaWeekStart(old.date) != agendaWeekStart(widget.date))
      positioned = false;
    if (agendaDay(old.date) != agendaDay(widget.date)) focusPositioned = false;
  }

  Widget block(AgendaEntry entry) {
    final colors = Theme.of(context).colorScheme;
    final conflict = agendaEntryConflicts(entry, widget.allEntries).isNotEmpty;
    // 与列表视图同一来源色：浅色底加左侧色条，课程、作业一眼可分。
    final source = agendaSourceColor(entry, colors);
    final color = Color.alphaBlend(
      source.withValues(alpha: .22),
      colors.surfaceContainerLow,
    );
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Tooltip(
        message:
            '${agendaTitle(entry)} · ${agendaWhen(entry)}${conflict ? ' · 与课程重叠' : ''}',
        child: Material(
          color: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: source.withValues(alpha: .35)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => widget.onOpen(entry),
            child: Builder(
              builder: (context) {
                final fg = colors.onSurface;
                final place =
                    entry.local?.content.location ?? entry.school?.location;
                final titleStyle = TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: fg,
                );
                final placeStyle = TextStyle(
                  fontSize: 9.5,
                  height: 1.2,
                  color: fg.withValues(alpha: .85),
                );
                return Container(
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: source, width: 3)),
                  ),
                  padding: const EdgeInsets.fromLTRB(4, 3, 2, 2),
                  // 按块高只排完整的行，避免末行被横向切掉一半；标题优先，地点用剩余行。
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scaler = MediaQuery.textScalerOf(context);
                      int linesOf(String text, TextStyle style, int max) {
                        final painter = TextPainter(
                          text: TextSpan(text: text, style: style),
                          textDirection: TextDirection.ltr,
                          textScaler: scaler,
                          maxLines: max,
                        )..layout(maxWidth: constraints.maxWidth);
                        final lines = painter.computeLineMetrics().length;
                        painter.dispose();
                        return lines;
                      }

                      double lineHeight(TextStyle style) =>
                          scaler.scale(style.fontSize!) * style.height!;
                      var title = agendaTitle(entry);
                      // 纯中文短标题按行数均分，避免“编译技/术”这样末行只剩一个字。
                      if (!title.contains(RegExp(r'[\x00-\x7F]'))) {
                        final lines = linesOf(title, titleStyle, 4);
                        final per = (title.length / lines).ceil();
                        if (lines > 1 && lines * per - title.length < per) {
                          title = [
                            for (var i = 0; i < title.length; i += per)
                              title.substring(
                                i,
                                (i + per).clamp(0, title.length),
                              ),
                          ].join('\n');
                        }
                      }
                      final titleLine = lineHeight(titleStyle);
                      final titleLines = (constraints.maxHeight / titleLine)
                          .floor()
                          .clamp(1, 4);
                      final usedTitle =
                          linesOf(title, titleStyle, titleLines) * titleLine;
                      final placeLines = place?.isNotEmpty == true
                          ? ((constraints.maxHeight - usedTitle) /
                                    lineHeight(placeStyle))
                                .floor()
                                .clamp(0, 2)
                          : 0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: titleLines,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                          if (placeLines > 0)
                            Text(
                              place!,
                              maxLines: placeLines,
                              overflow: TextOverflow.ellipsis,
                              style: placeStyle,
                            ),
                          if (conflict &&
                              constraints.maxHeight - usedTitle >= 12)
                            Icon(
                              Icons.event_busy_outlined,
                              size: 12,
                              color: fg,
                            ),
                        ],
                      );
                    },
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
    final placements =
        <({int day, _Slot slot, int lane, int lanes, DateTime base})>[];
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
      slots.removeWhere(
        (signin) => slots.any(
          (course) => agendaSigninMatches(
            signin.entry,
            course.entry,
            course.start,
            course.end,
          ),
        ),
      );
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
        for (var j = 0; j < group.length; j++)
          placements.add((
            day: i,
            slot: group[j],
            lane: lanes[j],
            lanes: ends.length,
            base: day,
          ));
      }
    }
    double hours(DateTime t, DateTime base) =>
        t.difference(base).inSeconds / 3600;
    firstHour = 8;
    lastHour = 23;
    for (final p in placements) {
      firstHour = math.min(
        firstHour,
        hours(p.slot.start, p.base).floor().clamp(0, 23),
      );
      lastHour = math.max(
        lastHour,
        hours(p.slot.displayEnd, p.base).ceil().clamp(1, 24),
      );
    }
    final starts = [
      for (final p in placements)
        if (p.slot.start.isAfter(p.base)) hours(p.slot.start, p.base),
    ];
    earliestStart = starts.isEmpty ? null : starts.reduce(math.min) - firstHour;
    final offset = firstHour * hourHeight;
    return [
      for (final p in placements)
        Positioned(
          key: ValueKey('agenda-week-${agendaEntryKey(p.slot.entry)}-${p.day}'),
          left: axis + p.day * column + p.lane * column / p.lanes,
          top: math.max(0, hours(p.slot.start, p.base) * hourHeight - offset),
          width: column / p.lanes,
          height: math.max(
            hourHeight / 2,
            hours(p.slot.end, p.base) * hourHeight -
                math.max(hours(p.slot.start, p.base) * hourHeight, offset),
          ),
          child: block(p.slot.entry),
        ),
    ];
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
      final placed = blocks(monday, column, axis, hourHeight);
      if (!positioned) {
        positioned = true;
        // 换周或首次显示时从最早开始的事项看起，上方留一刻钟。
        final target = math.max(0.0, (earliestStart ?? 0) - .25) * hourHeight;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && vertical.hasClients)
            vertical.jumpTo(
              math.min(target, vertical.position.maxScrollExtent),
            );
        });
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Scrollbar(
              controller: horizontal,
              thumbVisibility: width > constraints.maxWidth,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: horizontal,
                scrollDirection: Axis.horizontal,
                // 七列始终放满一屏，横向滑动留给日程页切换周次。
                physics: const NeverScrollableScrollPhysics(),
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
                      if (top.isNotEmpty)
                        _AllDayRow(
                          monday: monday,
                          entries: top,
                          allEntries: widget.allEntries,
                          axis: axis,
                          column: column,
                          onOpen: widget.onOpen,
                        ),
                      Expanded(
                        child: ListView(
                          controller: vertical,
                          key: const ValueKey('agenda-week-grid'),
                          // 不继承状态栏等安全区内边距，网格紧贴全天行。
                          padding: EdgeInsets.zero,
                          children: [
                            SevenDayTimeGrid(
                              rows: lastHour - firstHour,
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
                                    for (
                                      var hour = firstHour;
                                      hour < lastHour;
                                      hour++
                                    )
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
                              children: placed,
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

DateTime campusToday() => agendaDay(campusDate(clock.now()));

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
                    fontWeight: FontWeight.w500,
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

/// 周视图表头下的全天行：全天、截止与时间待定的事项落在各自那一天的列里。
///
/// 每天最多直接显示两项，其余收成「+N」，点开看当天全部；整周没有时不显示。
class _AllDayRow extends StatelessWidget {
  const _AllDayRow({
    required this.monday,
    required this.entries,
    required this.allEntries,
    required this.axis,
    required this.column,
    required this.onOpen,
  });
  final DateTime monday;
  final List<AgendaEntry> entries, allEntries;
  final double axis, column;
  final ValueChanged<AgendaEntry> onOpen;
  static const shown = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final days = List.generate(7, (_) => <AgendaEntry>[]);
    final undated = <AgendaEntry>[];
    for (final entry in entries) {
      final date = agendaEntryDate(entry);
      if (date == null) {
        undated.add(entry);
      } else {
        days[agendaDay(date).difference(monday).inDays.clamp(0, 6)].add(entry);
      }
    }
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: axis,
            child: undated.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '全天',
                      textAlign: TextAlign.center,
                      style: muted,
                    ),
                  )
                : InkWell(
                    onTap: () => _showList(context, '没有日期', undated),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '全天\n无日期 ${undated.length}',
                        textAlign: TextAlign.center,
                        style: muted,
                      ),
                    ),
                  ),
          ),
          for (var i = 0; i < 7; i++)
            SizedBox(
              width: column,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in days[i].take(shown))
                    _pill(context, entry),
                  if (days[i].length > shown)
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => _showList(
                        context,
                        agendaMonthDay(monday.add(Duration(days: i))),
                        days[i],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '+${days[i].length - shown}',
                          textAlign: TextAlign.center,
                          style: muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 窄列只放标题；宽列在截止事项前加时刻，时间待定的加「待定」。
  String _label(AgendaEntry entry) {
    final title = agendaTitle(entry);
    final timing = entry.timing;
    if (timing.kind == AgendaTimingKind.period) return '待定 $title';
    if (column < 90) return title;
    if (timing.kind == AgendaTimingKind.deadline && timing.due != null)
      return '${timing.due!.rfc3339.substring(11, 16)} $title';
    return title;
  }

  Widget _pill(BuildContext context, AgendaEntry entry) => AgendaEntryChip(
    entry: entry,
    label: _label(entry),
    conflict: agendaEntryConflicts(entry, allEntries).isNotEmpty,
    // 手机列宽只放得下三四个字，窄列允许两行。
    wrap: column < 90,
    onTap: () => onOpen(entry),
  );

  void _showList(BuildContext context, String title, List<AgendaEntry> items) =>
      showAgendaEntryList(
        context,
        title: title,
        entries: items,
        onOpen: onOpen,
      );
}

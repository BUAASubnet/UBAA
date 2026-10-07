import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'detail.dart' show uiShowScheduleDetails, uiShowScheduleGroup;
import 'flow.dart' show ScheduleWeekScope;
import '../../shared/schedule_values.dart' show uiScheduled;
import '../../shared/text.dart' show uiNonBlank;

/// 冻结旧版的七日节次网格；时间缺失或冲突不造成课程丢失。
class ScheduleContent extends StatefulWidget {
  const ScheduleContent({
    required this.details,
    this.timeline,
    this.timeSource,
    this.emptyMessage = '本周暂无课程',
  });
  final ScheduleWeekOverview? timeline;
  final List<FeatureDetail> details;
  final List<FeatureDetail>? timeSource;
  final String emptyMessage;
  @override
  State<ScheduleContent> createState() => _ScheduleContentState();
}

class _ScheduleContentState extends State<ScheduleContent> {
  final _horizontal = ScrollController();
  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      final dates = ScheduleWeekScope.of(context)?.headerDateLabels;
      final width = math.max(constraints.maxWidth - 16, 330 * scale);
      final periodHeight = 64 * scale;
      final times =
          widget.timeline?.sectionTimes ??
          scheduleSectionTimes(
            courses: (widget.timeSource ?? widget.details)
                .map((d) => d.presentation)
                .whereType<ScheduleCoursePresentation>(),
          );
      final axisWidth = 52 * scale;
      final columnWidth = (width - axisWidth) / 7;
      final groups = <_ScheduleBlock>[];
      final unknown = <FeatureDetail>[];
      var periods = math.max(12, times.length);
      for (final detail in widget.details) {
        final p = detail.presentation! as ScheduleCoursePresentation;
        if (!uiScheduled(p)) {
          unknown.add(detail);
          continue;
        }
        periods = math.max(periods, p.endSection!);
      }
      // 同一天相交的时间段合并为可打开的课程组，避免后画课程遮掉前者。
      for (var day = 1; day <= 7; day++) {
        final courses =
            widget.details.where((d) {
              final p = d.presentation! as ScheduleCoursePresentation;
              return uiScheduled(p) && p.dayOfWeek == day;
            }).toList()..sort(
              (a, b) => (a.presentation! as ScheduleCoursePresentation)
                  .beginSection!
                  .compareTo(
                    (b.presentation! as ScheduleCoursePresentation)
                        .beginSection!,
                  ),
            );
        for (final detail in courses) {
          final p = detail.presentation! as ScheduleCoursePresentation;
          if (groups.isNotEmpty &&
              groups.last.day == day &&
              p.beginSection! <= groups.last.end) {
            groups.last.end = math.max(groups.last.end, p.endSection!);
            groups.last.details.add(detail);
          } else {
            groups.add(
              _ScheduleBlock(day, p.beginSection!, p.endSection!, [detail]),
            );
          }
        }
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Scrollbar(
          controller: _horizontal,
          thumbVisibility: width > constraints.maxWidth - 16,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  SizedBox(
                    height: 52 * scale,
                    child: Row(
                      children: [
                        SizedBox(width: axisWidth),
                        for (final (index, label) in const [
                          '周一',
                          '周二',
                          '周三',
                          '周四',
                          '周五',
                          '周六',
                          '周日',
                        ].indexed)
                          Expanded(
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (dates?[index] case final date?)
                                    Text(
                                      date,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      key: const ValueKey('schedule-grid-scroll'),
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        if (widget.details.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: Text(widget.emptyMessage)),
                          ),
                        SizedBox(
                          height: periodHeight * periods,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _ScheduleLines(
                                    periods: periods,
                                    rowHeight: periodHeight,
                                    axisWidth: axisWidth,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: .1),
                                  ),
                                ),
                              ),
                              for (final (index, group) in groups.indexed)
                                Positioned(
                                  key: ValueKey('schedule-block-$index'),
                                  left:
                                      axisWidth + (group.day - 1) * columnWidth,
                                  top: (group.begin - 1) * periodHeight,
                                  width: columnWidth,
                                  height:
                                      (group.end - group.begin + 1) *
                                      periodHeight,
                                  child: _ScheduleCell(group: group),
                                ),
                              _SchedulePinnedAxis(
                                controller: _horizontal,
                                width: axisWidth,
                                rowHeight: periodHeight,
                                periods: periods,
                                times: times,
                              ),
                            ],
                          ),
                        ),
                        if (unknown.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: AnimatedBuilder(
                              animation: _horizontal,
                              child: SizedBox(
                                width: constraints.maxWidth - 16,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Text('时间待确认'),
                                    ),
                                    for (final detail in unknown)
                                      Card(
                                        child: ListTile(
                                          title: Text(detail.title),
                                          subtitle: Text(
                                            uiNonBlank(
                                                  (detail.presentation!
                                                          as ScheduleCoursePresentation)
                                                      .place,
                                                ) ??
                                                '地点待公布',
                                          ),
                                          trailing: const Icon(
                                            Icons.chevron_right,
                                          ),
                                          onTap: () => uiShowScheduleDetails(
                                            context,
                                            detail,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              builder: (context, child) => Transform.translate(
                                offset: Offset(
                                  _horizontal.hasClients
                                      ? _horizontal.offset
                                      : 0,
                                  0,
                                ),
                                child: child,
                              ),
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
      );
    },
  );
}

class _SchedulePinnedAxis extends AnimatedWidget {
  const _SchedulePinnedAxis({
    required this.controller,
    required this.width,
    required this.rowHeight,
    required this.periods,
    required this.times,
  }) : super(listenable: controller);
  final ScrollController controller;
  final List<ScheduleSectionTime> times;
  final double width, rowHeight;
  final int periods;
  @override
  Widget build(BuildContext context) => Positioned(
    left: controller.hasClients ? controller.offset : 0,
    top: 0,
    bottom: 0,
    width: width,
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          for (var section = 1; section <= periods; section++)
            SizedBox(
              height: rowHeight,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$section',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      section <= times.length
                          ? times[section - 1].start ?? '--:--'
                          : '--:--',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.3,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      section <= times.length
                          ? times[section - 1].end ?? '--:--'
                          : '--:--',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.3,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _ScheduleBlock {
  _ScheduleBlock(this.day, this.begin, this.end, this.details);
  final int day, begin;
  int end;
  final List<FeatureDetail> details;
}

class _ScheduleCell extends StatelessWidget {
  const _ScheduleCell({required this.group});
  final _ScheduleBlock group;
  @override
  Widget build(BuildContext context) {
    final detail = group.details.first;
    final p = detail.presentation! as ScheduleCoursePresentation;
    final raw = p.color?.trim() ?? '';
    final parsed = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(raw)
        ? Color(0xFF000000 | int.parse(raw.substring(1), radix: 16))
        : null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = parsed == null
        ? const Color(0xFF6200EE)
        : dark
        ? parsed.withValues(alpha: .7)
        : parsed;
    final foreground = background.computeLuminance() > .5
        ? Colors.black
        : Colors.white;
    final multiple = group.details.length > 1;
    final short = group.end == group.begin;
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => multiple
              ? uiShowScheduleGroup(context, group.details)
              : uiShowScheduleDetails(context, detail),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    multiple ? '${group.details.length}门课程' : detail.title,
                    textAlign: TextAlign.center,
                    maxLines: short ? 2 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 14 / 12,
                      fontWeight: FontWeight.bold,
                      color: foreground,
                    ),
                  ),
                ),
                if (!short && multiple)
                  Text(
                    '点击查看',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: foreground),
                  ),
                if (!multiple && uiNonBlank(p.place) != null)
                  Flexible(
                    child: Text(
                      '@${p.place}',
                      textAlign: TextAlign.center,
                      maxLines: short ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 13 / 11,
                        color: foreground.withValues(alpha: .8),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScheduleLines extends CustomPainter {
  _ScheduleLines({
    required this.periods,
    required this.rowHeight,
    required this.axisWidth,
    required this.color,
  });
  final int periods;
  final double rowHeight, axisWidth;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final column = (size.width - axisWidth) / 7;
    for (var day = 0; day <= 7; day++) {
      final x = axisWidth + day * column;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var row = 1; row < periods; row++) {
      for (var x = axisWidth; x < size.width; x += 10) {
        canvas.drawLine(
          Offset(x, row * rowHeight),
          Offset(math.min(x + 5, size.width), row * rowHeight),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ScheduleLines old) =>
      periods != old.periods ||
      rowHeight != old.rowHeight ||
      axisWidth != old.axisWidth ||
      color != old.color;
}

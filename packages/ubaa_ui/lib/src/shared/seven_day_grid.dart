import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 课表和日程共用七日网格、日期列高亮及固定时间轴。
class SevenDayTimeGrid extends StatelessWidget {
  const SevenDayTimeGrid({
    super.key,
    required this.rows,
    required this.rowHeight,
    required this.axisWidth,
    required this.children,
    required this.axis,
    this.today,
  });
  final int rows;
  final double rowHeight, axisWidth;
  final int? today;
  final List<Widget> children;
  final Widget axis;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: rows * rowHeight,
    child: Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _SevenDayLines(
              rows: rows,
              rowHeight: rowHeight,
              axisWidth: axisWidth,
              today: today,
              todayColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .06),
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: .1),
            ),
          ),
        ),
        ...children,
        axis,
      ],
    ),
  );
}

class PinnedWeekAxis extends AnimatedWidget {
  const PinnedWeekAxis({
    super.key,
    required this.controller,
    required this.width,
    required this.child,
  }) : super(listenable: controller);
  final ScrollController controller;
  final double width;
  final Widget child;
  @override
  Widget build(BuildContext context) => Positioned(
    left: controller.hasClients ? controller.offset : 0,
    top: 0,
    bottom: 0,
    width: width,
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: child,
    ),
  );
}

class _SevenDayLines extends CustomPainter {
  _SevenDayLines({
    required this.rows,
    required this.rowHeight,
    required this.axisWidth,
    required this.color,
    required this.todayColor,
    this.today,
  });
  final int rows;
  final int? today;
  final double rowHeight, axisWidth;
  final Color color, todayColor;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final column = (size.width - axisWidth) / 7;
    if (today case final index?) {
      canvas.drawRect(
        Rect.fromLTWH(axisWidth + index * column, 0, column, size.height),
        Paint()..color = todayColor,
      );
    }
    for (var day = 0; day <= 7; day++) {
      final x = axisWidth + day * column;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var row = 1; row < rows; row++) {
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
  bool shouldRepaint(_SevenDayLines old) =>
      rows != old.rows ||
      rowHeight != old.rowHeight ||
      axisWidth != old.axisWidth ||
      today != old.today ||
      color != old.color ||
      todayColor != old.todayColor;
}

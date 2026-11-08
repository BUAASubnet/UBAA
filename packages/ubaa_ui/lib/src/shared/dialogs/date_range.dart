import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'sheet.dart' show uiPrefersDialog;

/// 日期范围选择：窄窗口保持全屏日历；宽窗口收成居中卡片，不铺满整个桌面窗口。
Future<DateTimeRange?> uiShowDateRangePicker(
  BuildContext context, {
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
  String? helpText,
  String? saveText,
  TransitionBuilder? builder,
}) {
  final compact = !uiPrefersDialog(context);
  return showDateRangePicker(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    initialDateRange: initialDateRange,
    helpText: helpText,
    saveText: saveText,
    builder: (context, child) {
      final picker = builder?.call(context, child) ?? child!;
      if (compact) return picker;
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: math.min(MediaQuery.sizeOf(context).height * .85, 640),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: picker,
            ),
          ),
        ),
      );
    },
  );
}

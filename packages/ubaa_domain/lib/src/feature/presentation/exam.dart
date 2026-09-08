part of '../presentation.dart';

final class ExamPresentation extends FeaturePresentation {
  const ExamPresentation({
    required this.arranged,
    this.courseNo,
    this.date,
    this.description,
    this.startTime,
    this.endTime,
    this.place,
    this.seat,
    this.week,
    this.status,
    this.type,
    this.taskId,
  });

  final bool arranged;
  final String? courseNo;
  final String? date;
  final String? description;
  final String? startTime;
  final String? endTime;
  final String? place;
  final String? seat;
  final int? week;
  final int? status;
  final String? type;
  final String? taskId;

  /// 旧版只读取日期中空格前的部分；越界日期不能自动归一化。
  DateTime? get calendarDate {
    final value = date?.split(' ').first;
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        parsed.year != int.parse(value.substring(0, 4)) ||
        parsed.month != int.parse(value.substring(5, 7)) ||
        parsed.day != int.parse(value.substring(8, 10))) {
      return null;
    }
    return parsed;
  }

  /// 沿旧版严格晚于结束时刻；缺失/非法结束时间按当日23:59处理。
  bool isFinishedAt(DateTime now) {
    if (!arranged) return false;
    final day = calendarDate;
    if (day == null) return false;
    final time = RegExp(
      r'^(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,9}))?)?$',
    ).firstMatch(endTime ?? '');
    final hour = time == null ? 24 : int.parse(time[1]!);
    final minute = time == null ? 60 : int.parse(time[2]!);
    final second = int.parse(time?[3] ?? '0');
    final valid = hour < 24 && minute < 60 && second < 60;
    final fraction = (time?[4] ?? '').padRight(6, '0').substring(0, 6);
    final end = DateTime(
      day.year,
      day.month,
      day.day,
      valid ? hour : 23,
      valid ? minute : 59,
      valid ? second : 0,
      0,
      valid ? int.parse(fraction) : 0,
    );
    return now.isAfter(end);
  }
}

part of '../presentation.dart';

final class TodayCoursePresentation extends FeaturePresentation {
  const TodayCoursePresentation({this.time, this.place});

  final String? time;
  final String? place;
}

final class TermPresentation extends FeaturePresentation {
  const TermPresentation({
    required this.code,
    required this.selected,
    required this.index,
  });

  final String code;
  final bool selected;
  final int index;
}

final class WeekPresentation extends FeaturePresentation {
  const WeekPresentation({
    required this.requestTerm,
    required this.responseTerm,
    required this.number,
    required this.current,
    required this.startDate,
    required this.endDate,
  });

  final String requestTerm;
  final String responseTerm;
  final int number;
  final bool current;
  final String startDate;
  final String endDate;

  /// 沿冻结旧版只用本周真实起止日期；UTC日历运算避免夏令时跨日偏移。
  List<String?> get headerDateLabels {
    final start =
        _parseWeekDate(startDate) ??
        _parseWeekDate(endDate)?.subtract(const Duration(days: 6));
    if (start == null) return List.unmodifiable(List<String?>.filled(7, null));
    return List.unmodifiable(
      List.generate(7, (index) {
        final date = start.add(Duration(days: index));
        return '${date.month}-${date.day}';
      }),
    );
  }
}

DateTime? _parseWeekDate(String raw) {
  final match = RegExp(
    r'(\d{4})\D+(\d{1,2})\D+(\d{1,2})',
  ).firstMatch(raw.trim());
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final parsed = DateTime.utc(year, month, day);
  return parsed.year == year && parsed.month == month && parsed.day == day
      ? parsed
      : null;
}

final class ScheduleCoursePresentation extends FeaturePresentation {
  const ScheduleCoursePresentation({
    required this.courseCode,
    this.courseSerialNo,
    this.credit,
    this.beginTime,
    this.endTime,
    this.beginSection,
    this.endSection,
    this.dayOfWeek,
    this.place,
    this.weeksAndTeachers,
    this.teachingTarget,
    this.color,
  });

  final String courseCode;
  final String? courseSerialNo;
  final String? credit;
  final String? beginTime;
  final String? endTime;
  final int? beginSection;
  final int? endSection;
  final int? dayOfWeek;
  final String? place;
  final String? weeksAndTeachers;
  final String? teachingTarget;
  final String? color;
}

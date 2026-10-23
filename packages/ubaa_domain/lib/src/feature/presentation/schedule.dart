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

final class ScheduleSectionTime {
  const ScheduleSectionTime(this.section, this.start, this.end);
  final int section;
  final String? start, end;
}

/// 明确作息及课程边界优先；缺失时间按用户提供的 2026—2027 校历补齐。
List<ScheduleSectionTime> scheduleSectionTimes({
  required Iterable<ScheduleCoursePresentation> courses,
  List<ScheduleSectionTime> explicit = const [],
  String? code,
}) {
  const standard = [
    ('08:00', '08:45'),
    ('08:50', '09:35'),
    ('09:50', '10:35'),
    ('10:40', '11:25'),
    ('11:30', '12:15'),
    ('14:00', '14:45'),
    ('14:50', '15:35'),
    ('15:50', '16:35'),
    ('16:40', '17:25'),
    ('17:30', '18:15'),
    ('19:00', '19:45'),
    ('19:50', '20:35'),
    ('20:40', '21:25'),
    ('21:30', '22:15'),
  ];
  final times = explicit;
  var count = standard.length;
  for (final time in times) {
    if (time.section > count) count = time.section;
  }
  for (final course in courses) {
    if ((course.endSection ?? 0) > count) count = course.endSection!;
  }
  String? single(Iterable<String?> values) {
    final unique = values.whereType<String>().toSet();
    return unique.length == 1 ? unique.single : null;
  }

  String? boundary(
    Iterable<String?> known,
    Iterable<String?> observed,
    String? fallback,
  ) {
    final values = known.whereType<String>().toList();
    if (values.isNotEmpty) return single(values);
    final courseValues = observed.whereType<String>().toList();
    return courseValues.isEmpty ? fallback : single(courseValues);
  }

  return List.unmodifiable(
    List.generate(count, (index) {
      final section = index + 1;
      final known = times.where((t) => t.section == section).toList();
      return ScheduleSectionTime(
        section,
        boundary(
          known.map((t) => t.start),
          courses
              .where((c) => c.beginSection == section)
              .map((c) => c.beginTime),
          index < standard.length ? standard[index].$1 : null,
        ),
        boundary(
          known.map((t) => t.end),
          courses.where((c) => c.endSection == section).map((c) => c.endTime),
          index < standard.length ? standard[index].$2 : null,
        ),
      );
    }),
  );
}

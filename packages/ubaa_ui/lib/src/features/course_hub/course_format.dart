import 'package:ubaa_domain/ubaa_domain.dart';

import '../../shared/schedule_values.dart' show uiWeekdays;
import '../../shared/text.dart' show uiNonBlank;
import '../../shared/when.dart' show uiClock, uiDay, uiParseCampusTime;

/// 作业在课程中心里的三种去向，口径与 SPOC、希冀列表的默认筛选一致：
/// 未提交（希冀含部分提交）且未过截止 → 待交；未提交且已过截止 → 已截止未交；
/// 其余（已提交、状态未知）→ 其他。
enum CourseHubBucket { pending, overdue, other }

CourseHubBucket courseHubBucket(FeatureDetail detail, DateTime now) {
  final (status, due, spoc) = switch (detail.presentation) {
    SpocAssignmentPresentation p => (p.status, p.dueTime, true),
    JudgeAssignmentPresentation p => (p.status, p.dueTime, false),
    _ => (AssignmentSubmissionStatus.unknown, null, true),
  };
  final unfinished =
      status == AssignmentSubmissionStatus.unsubmitted ||
      (!spoc && status == AssignmentSubmissionStatus.partial);
  if (!unfinished) return CourseHubBucket.other;
  final deadline = uiParseCampusTime(due);
  if (deadline != null && !deadline.isAfter(now)) {
    return CourseHubBucket.overdue;
  }
  return CourseHubBucket.pending;
}

DateTime? courseHubDue(FeatureDetail detail) =>
    uiParseCampusTime(switch (detail.presentation) {
      SpocAssignmentPresentation p => p.dueTime,
      JudgeAssignmentPresentation p => p.dueTime,
      _ => null,
    });

/// 截止时间升序；没有截止时间的排在最后，再按标题稳定排序。
int courseHubByDue(FeatureDetail a, FeatureDetail b) {
  final x = courseHubDue(a), y = courseHubDue(b);
  final order = x == null
      ? (y == null ? 0 : 1)
      : (y == null ? -1 : x.compareTo(y));
  return order != 0 ? order : a.title.compareTo(b.title);
}

String courseHubAssignmentCourse(FeatureDetail detail) =>
    switch (detail.presentation) {
      SpocAssignmentPresentation p => p.courseName,
      JudgeAssignmentPresentation p => p.courseName,
      _ => '',
    };

/// 课程中心给出的是时刻（UTC），显示前换成校园时区的钟面时间。
DateTime courseHubCampus(DateTime instant) => homeCampusTime(instant);

/// “14:00”：时刻按校园时区显示。
String courseHubClock(DateTime instant) => uiClock(courseHubCampus(instant));

/// “今天 14:00” “明天 08:00” “周三 09:50” “12月3日 08:00”。
/// instant 是时刻；now 是校园钟面时间（uiCampusNow 的结果）。
String courseHubWhen(DateTime instant, DateTime now) {
  final start = courseHubCampus(instant);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(start.year, start.month, start.day);
  final days = day.difference(today).inDays;
  final label = switch (days) {
    0 => '今天',
    1 => '明天',
    2 => '后天',
    < 7 => '周${'一二三四五六日'[start.weekday - 1]}',
    _ => uiDay(start, now: now),
  };
  return '$label ${uiClock(start)}';
}

/// 一条每周排课：“星期三 · 第 3–4 节 · 09:50–11:25”。
String? courseHubSlotWhen(ScheduleCoursePresentation p) {
  final day = p.dayOfWeek;
  final parts = [
    if (day != null && day >= 1 && day <= 7) uiWeekdays[day - 1],
    if (p.beginSection case final s?)
      p.endSection == null || p.endSection == s
          ? '第 $s 节'
          : '第 $s–${p.endSection} 节',
    if (uiNonBlank(p.beginTime) case final b?)
      if (uiNonBlank(p.endTime) case final e?) '$b–$e' else b,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// 教师名统一用顿号分隔；上游有的用逗号连写在一个字段里。
String? courseHubTeachers(List<String> teachers) {
  final names = [
    for (final t in teachers)
      for (final n in t.split(RegExp(r'\s*[,，、]\s*')))
        if (n.trim().isNotEmpty) n.trim(),
  ];
  return names.isEmpty ? null : {...names}.join('、');
}

import '../data_evidence.dart';
import '../presentation.dart';
import '../result.dart';
import '../schedule/home.dart';

enum SigninPhase {
  upcoming,
  open,
  ended,
  unknown,
  completed,
  completedOpen;

  bool get isCompleted => this == completed || this == completedOpen;
  bool get canOpenQr => this == open || this == completedOpen;
}

/// 依据校园墙上时间判断二维码是否开放，不授予学校写入资格。
SigninPhase signinPhase(SigninPresentation course, DateTime campusNow) {
  final completed = course.signStatus == 1;
  if (!completed && course.signStatus != 0) return SigninPhase.unknown;
  final start = _parseCampusTime(course.classBeginTime, campusNow);
  final end = _parseCampusTime(course.classEndTime, campusNow);
  if (start == null || end == null || end.isBefore(start)) {
    return completed ? SigninPhase.completed : SigninPhase.unknown;
  }
  if (campusNow.isAfter(end)) {
    return completed ? SigninPhase.completed : SigninPhase.ended;
  }
  if (course.actionTarget?.trim().isEmpty ?? true) {
    return completed ? SigninPhase.completed : SigninPhase.unknown;
  }
  if (campusNow.isBefore(start.subtract(const Duration(minutes: 10)))) {
    return completed ? SigninPhase.completed : SigninPhase.upcoming;
  }
  return completed ? SigninPhase.completedOpen : SigninPhase.open;
}

/// 只从同日成功的在线快照取得签到课程，不使用缓存编号重建目标。
FeatureDetail? freshSigninDetail(
  FeatureSnapshot? source, {
  required String? courseId,
  required String date,
}) {
  if (courseId == null ||
      source == null ||
      source.resolvedRoute == null ||
      source.status != FeatureLoadStatus.success ||
      source.evidence?.origin == DataOrigin.persisted ||
      source.evidence?.complete == false)
    return null;
  final updatedAt = source.updatedAt;
  final scopeDate =
      source.evidence?.scopeDate ??
      (updatedAt == null ? null : homeDateKey(homeCampusTime(updatedAt)));
  if (scopeDate != null && scopeDate != date) return null;
  final matches = source.details.where((detail) {
    final course = detail.presentation;
    return course is SigninPresentation && course.courseId == courseId;
  }).toList();
  return matches.length == 1 ? matches.single : null;
}

final _campusTime = RegExp(
  r'^(?:(\d{4}-\d{2}-\d{2})[ T])?(\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d{1,9}))?)?$',
);

DateTime? _parseCampusTime(String raw, DateTime day) {
  final match = _campusTime.firstMatch(raw.trim());
  if (match == null) return null;
  final date = match[1] == null ? day : homeParseDate(match[1]!);
  final hour = int.parse(match[2]!);
  final minute = int.parse(match[3]!);
  final second = int.parse(match[4] ?? '0');
  if (date == null || hour > 23 || minute > 59 || second > 59) return null;
  final micros = int.parse((match[5] ?? '').padRight(6, '0').substring(0, 6));
  final makeTime = day.isUtc ? DateTime.utc : DateTime.new;
  return makeTime(
    date.year,
    date.month,
    date.day,
    hour,
    minute,
    second,
  ).add(Duration(microseconds: micros));
}

import '../write/actions.dart';
import 'catalog.dart';
import 'presentation.dart';
import 'result.dart';
import 'overview.dart';
import 'query.dart';
import 'read_navigation.dart';

/// 首页额外读取只允许旧版已有的三类来源。
enum HomeSupplement { bykcChosen, cgyyOrders, currentWeek }

/// 首页提醒只使用公开读结果；不能由时间或进度授予学校写入资格。
final class HomeTodo {
  const HomeTodo({
    required this.id,
    required this.feature,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.timeLabel,
    required this.sortTime,
    this.navigation,
    this.signinAction,
  });
  final String id, title, subtitle, statusLabel, timeLabel;
  final FeatureId feature;
  final DateTime sortTime;
  final FeatureReadNavigation? navigation;
  final SigninPerformAction? signinAction;
}

List<HomeTodo> buildHomeTodos({
  required Map<FeatureId, FeatureSnapshot> snapshots,
  required DateTime now,
  WeekPresentation? currentWeek,
  bool ygdkReminderEnabled = true,
  bool ygdkWeekDone = false,
  bool ygdkTermDone = false,
}) {
  final result = <HomeTodo>[];
  for (final feature in [
    FeatureId.bykc,
    FeatureId.spoc,
    FeatureId.judge,
    FeatureId.cgyy,
    FeatureId.signin,
  ]) {
    final snapshot = snapshots[feature];
    if (!_isHomeSource(snapshot)) continue;
    for (final detail in snapshot!.details) {
      final item = _homeDetail(
        feature,
        detail,
        now,
        fresh: snapshot.status == FeatureLoadStatus.success,
      );
      if (item != null) result.add(item);
    }
  }
  final sunlight = snapshots[FeatureId.ygdk];
  final overview = sunlight?.overview;
  final week = currentWeek;
  if (_isHomeSource(sunlight) &&
      overview is YgdkOverview &&
      week != null &&
      week.current &&
      week.responseTerm.trim().isNotEmpty &&
      week.number >= 11 &&
      week.number <= 14 &&
      ygdkReminderEnabled &&
      !ygdkWeekDone &&
      !ygdkTermDone &&
      overview.weekCount != null &&
      overview.weekCount! < 4 &&
      overview.termCount < 16) {
    final sunday = DateTime(
      now.year,
      now.month,
      now.day + 7 - now.weekday,
      23,
      59,
      59,
    );
    result.add(
      HomeTodo(
        id: 'ygdk:${week.responseTerm}:${week.number}',
        feature: FeatureId.ygdk,
        title: '本周阳光打卡未达标',
        subtitle: '本周已打卡 ${overview.weekCount} / 4 次',
        statusLabel: '待打卡',
        timeLabel: '截止 ${_formatHomeTime(sunday)}',
        sortTime: sunday,
        navigation: const FeatureReadNavigation(
          feature: FeatureId.ygdk,
          query: FeatureQuery(),
        ),
      ),
    );
  }
  // Dart排序不保证稳定；时间相同沿旧来源和原响应顺序。
  final ordered = result.indexed.toList()
    ..sort((a, b) {
      final time = a.$2.sortTime.compareTo(b.$2.sortTime);
      return time == 0 ? a.$1.compareTo(b.$1) : time;
    });
  return List.unmodifiable(ordered.map((e) => e.$2));
}

bool _isHomeSource(FeatureSnapshot? snapshot) {
  if (snapshot == null ||
      (snapshot.status != FeatureLoadStatus.success &&
          snapshot.status != FeatureLoadStatus.stale &&
          !(snapshot.status == FeatureLoadStatus.loading &&
              snapshot.updatedAt != null)))
    return false;
  final query = snapshot.readContext?.query;
  return switch (snapshot.feature) {
    FeatureId.bykc => query?.view == FeatureQueryView.bykcChosenCourses,
    FeatureId.cgyy => query?.view == FeatureQueryView.cgyyOrders,
    FeatureId.spoc ||
    FeatureId.judge ||
    FeatureId.ygdk ||
    FeatureId.signin => query == null || query.view == FeatureQueryView.summary,
    _ => false,
  };
}

HomeTodo? _homeDetail(
  FeatureId feature,
  FeatureDetail detail,
  DateTime now, {
  required bool fresh,
}) {
  final p = detail.presentation;
  if (feature == FeatureId.bykc && p is BykcChosenPresentation) {
    final start = _parseHomeTime(p.courseStartDate),
        end = _parseHomeTime(p.courseEndDate);
    if ((start == null && end == null) || end?.isBefore(now) == true)
      return null;
    final ongoing = start != null && !start.isAfter(now);
    return HomeTodo(
      id: 'bykc:${p.courseId}',
      feature: feature,
      title: p.courseName,
      subtitle: _joinHome([p.courseTeacher, p.coursePosition], '我的课程'),
      statusLabel: ongoing ? '进行中' : '即将开始',
      timeLabel: _homeRange(start, end),
      sortTime: start ?? end!,
      navigation: p.courseId <= 0
          ? null
          : FeatureReadNavigation(
              feature: feature,
              query: FeatureQuery(
                view: FeatureQueryView.bykcDetail,
                courseId: '${p.courseId}',
              ),
            ),
    );
  }
  if (feature == FeatureId.spoc &&
      p is SpocAssignmentPresentation &&
      !p.isDetail) {
    final start = _parseHomeTime(p.startTime), due = _parseHomeTime(p.dueTime);
    if (p.status != AssignmentSubmissionStatus.unsubmitted ||
        start?.isAfter(now) == true ||
        due == null ||
        !due.isAfter(now))
      return null;
    return HomeTodo(
      id: 'spoc:${p.assignmentId}',
      feature: feature,
      title: detail.title,
      subtitle: _joinHome([p.courseName, p.teacherName], 'SPOC 作业'),
      statusLabel: '待提交',
      timeLabel: '截止 ${_formatHomeTime(due)}',
      sortTime: due,
      navigation: p.assignmentId.trim().isEmpty
          ? null
          : FeatureReadNavigation(
              feature: feature,
              query: FeatureQuery(
                view: FeatureQueryView.spocDetail,
                assignmentId: p.assignmentId,
              ),
            ),
    );
  }
  if (feature == FeatureId.judge &&
      p is JudgeAssignmentPresentation &&
      !p.isDetail) {
    final due = _parseHomeTime(p.dueTime);
    if ((p.status != AssignmentSubmissionStatus.unsubmitted &&
            p.status != AssignmentSubmissionStatus.partial) ||
        due == null ||
        !due.isAfter(now))
      return null;
    return HomeTodo(
      id: 'judge:${p.courseId}:${p.assignmentId}',
      feature: feature,
      title: detail.title,
      subtitle: _joinHome([p.courseName], '希冀作业'),
      statusLabel: p.status == AssignmentSubmissionStatus.partial
          ? '待完成'
          : '待提交',
      timeLabel: '截止 ${_formatHomeTime(due)}',
      sortTime: due,
      navigation: p.courseId.trim().isEmpty || p.assignmentId.trim().isEmpty
          ? null
          : FeatureReadNavigation(
              feature: feature,
              query: FeatureQuery(
                view: FeatureQueryView.judgeDetail,
                courseId: p.courseId,
                assignmentId: p.assignmentId,
              ),
            ),
    );
  }
  if (feature == FeatureId.cgyy && p is CgyyOrderPresentation) {
    final start = _parseHomeTime(p.reservationStartDate),
        end = _parseHomeTime(p.reservationEndDate);
    if ((p.checkStatus ?? 0) < 0 ||
        p.orderStatus == 2 ||
        (end != null && !end.isAfter(now)) ||
        (start == null && end == null))
      return null;
    return HomeTodo(
      id: 'cgyy:${p.id}',
      feature: feature,
      title: _joinHome(
        [p.venueName, p.venueSpaceName ?? p.siteName],
        '研讨室预约',
        separator: ' / ',
      ),
      subtitle: _joinHome([p.theme, p.purposeTypeName], '我的预约'),
      statusLabel: start != null && !start.isAfter(now) ? '使用中' : '待使用',
      timeLabel: _homeRange(start, end),
      sortTime: start ?? end!,
      navigation: const FeatureReadNavigation(
        feature: FeatureId.cgyy,
        query: FeatureQuery(view: FeatureQueryView.cgyyOrders),
      ),
    );
  }
  if (feature == FeatureId.signin && p is SigninPresentation) {
    final start = _parseHomeTime(p.classBeginTime, today: now),
        end = _parseHomeTime(p.classEndTime, today: now);
    if (p.signStatus != 0 ||
        start == null ||
        end == null ||
        !now.isBefore(end) ||
        now.isBefore(start.subtract(const Duration(minutes: 10))))
      return null;
    final actions = detail.actions.whereType<SigninPerformAction>().toList();
    final action = actions.length == 1 ? actions.single : null;
    return HomeTodo(
      id: 'signin:${p.courseId}',
      feature: feature,
      title: detail.title,
      subtitle: '课程签到',
      statusLabel: now.isBefore(start) ? '即将签到' : '签到中',
      timeLabel: '${_clockHome(start)}–${_clockHome(end)}',
      sortTime: start,
      signinAction:
          fresh &&
              action?.eligibility == ActionEligibility.allowed &&
              action!.scheduleId.trim().isNotEmpty
          ? action
          : null,
    );
  }
  return null;
}

String _joinHome(
  List<String?> values,
  String fallback, {
  String separator = ' · ',
}) {
  final joined = values
      .whereType<String>()
      .where((v) => v.trim().isNotEmpty)
      .join(separator);
  return joined.isEmpty ? fallback : joined;
}

String _clockHome(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
String _formatHomeTime(DateTime? value) => value == null
    ? '时间待定'
    : '${value.month}月${value.day}日 ${_clockHome(value)}';
String _homeRange(DateTime? start, DateTime? end) {
  if (start == null || end == null) return '开始 ${_formatHomeTime(start)}';
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  return '${_formatHomeTime(start)}–${sameDay ? _clockHome(end) : _formatHomeTime(end)}';
}

/// 旧LocalDateTime接受的日期和钟点；拒绝Dart自动归一化越界日期。
DateTime? _parseHomeTime(String? value, {DateTime? today}) {
  final text = value?.trim() ?? '';
  final full = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?$',
  ).firstMatch(text);
  int year, month, day, hour, minute, second;
  if (full != null) {
    year = int.parse(full[1]!);
    month = int.parse(full[2]!);
    day = int.parse(full[3]!);
    hour = int.parse(full[4]!);
    minute = int.parse(full[5]!);
    second = int.parse(full[6] ?? '0');
  } else {
    final clock = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(text);
    if (today == null || clock == null) return null;
    year = today.year;
    month = today.month;
    day = today.day;
    hour = int.parse(clock[1]!);
    minute = int.parse(clock[2]!);
    second = int.parse(clock[3] ?? '0');
  }
  final result = DateTime(year, month, day, hour, minute, second);
  if (result.year != year ||
      result.month != month ||
      result.day != day ||
      result.hour != hour ||
      result.minute != minute ||
      result.second != second)
    return null;
  return result;
}

/// 本地提醒偏好与已观察到的达标记忆；不表示学校提交成功。
final class YgdkReminderSettings {
  const YgdkReminderSettings({
    this.enabled = true,
    this.weekDoneKey,
    this.termDoneKey,
  });
  final bool enabled;
  final String? weekDoneKey, termDoneKey;
  YgdkReminderSettings copyWith({
    bool? enabled,
    String? weekDoneKey,
    String? termDoneKey,
  }) => YgdkReminderSettings(
    enabled: enabled ?? this.enabled,
    weekDoneKey: weekDoneKey ?? this.weekDoneKey,
    termDoneKey: termDoneKey ?? this.termDoneKey,
  );
}

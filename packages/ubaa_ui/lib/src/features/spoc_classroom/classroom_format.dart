import 'package:ubaa_domain/ubaa_domain.dart';

/// 课堂页的展示格式：时间、周次分组与状态说明。只做展示，不产生任何资格判断。

DateTime sessionStart(ClassroomSessionSummary s) =>
    DateTime.fromMillisecondsSinceEpoch(s.startSecs * 1000);

DateTime sessionEnd(ClassroomSessionSummary s) =>
    DateTime.fromMillisecondsSinceEpoch(s.endSecs * 1000);

String _two(int v) => v.toString().padLeft(2, '0');

String clockLabel(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String sessionTimeRange(ClassroomSessionSummary s) =>
    '${clockLabel(sessionStart(s))}–${clockLabel(sessionEnd(s))}';

const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String weekdayLabel(DateTime t) => _weekdays[t.weekday - 1];

final _period = RegExp(r'第([0-9,，、\-]+)节\s*$');

/// 节次行的主文字：标题末尾若是“第8,9节”就只显示这一段（日期、周次已在别处），否则用整段标题。
String sessionPeriodLabel(ClassroomSessionSummary s) {
  final match = _period.firstMatch(s.title.trim());
  if (match == null) return s.title.trim().isEmpty ? '课堂' : s.title.trim();
  return '第${match.group(1)}节';
}

String playbackSourceLabel(ClassroomPlaybackKind kind) => switch (kind) {
  ClassroomPlaybackKind.teacher => '教师',
  ClassroomPlaybackKind.slides => 'PPT',
  ClassroomPlaybackKind.student => '学生',
};

bool sessionPlayable(ClassroomStatus status) =>
    status == ClassroomStatus.replay || status == ClassroomStatus.live;

String? sessionUnavailableHint(ClassroomStatus status) => switch (status) {
  ClassroomStatus.upcoming => '还没开始上课',
  ClassroomStatus.noReplay => '本节没有回放',
  ClassroomStatus.tencentMeeting => '腾讯会议节次请在腾讯会议中观看',
  ClassroomStatus.other => '本节暂时无法播放',
  ClassroomStatus.replay || ClassroomStatus.live => null,
};

final class SessionWeekGroup {
  const SessionWeekGroup(this.label, this.sessions);
  final String label;
  final List<ClassroomSessionSummary> sessions;
}

/// 按教学周分组：有周次用“第 N 周”，否则按自然周（周一起）显示起始日期。
/// 新周在上；同一周内按上课时间先后。
List<SessionWeekGroup> groupSessionsByWeek(
  List<ClassroomSessionSummary> sessions,
) {
  final sorted = [...sessions]
    ..sort((a, b) => b.startSecs.compareTo(a.startSecs));
  final order = <String>[];
  final buckets = <String, List<ClassroomSessionSummary>>{};
  final labels = <String, String>{};
  for (final s in sorted) {
    final String key, label;
    if (s.week != null) {
      key = 'w${s.week}';
      label = '第 ${s.week} 周';
    } else {
      final start = sessionStart(s);
      final monday = DateTime(
        start.year,
        start.month,
        start.day,
      ).subtract(Duration(days: start.weekday - 1));
      key = 'd${monday.year}-${monday.month}-${monday.day}';
      label = '${monday.month}/${monday.day} 起的一周';
    }
    if (!buckets.containsKey(key)) {
      order.add(key);
      buckets[key] = [];
      labels[key] = label;
    }
    buckets[key]!.add(s);
  }
  return [
    for (final key in order)
      SessionWeekGroup(
        labels[key]!,
        buckets[key]!..sort((a, b) => a.startSecs.compareTo(b.startSecs)),
      ),
  ];
}

/// 播放位置（毫秒或时长）显示为 mm:ss 或 h:mm:ss。
String mediaClock(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
}

import 'dart:convert';

int widgetDayStart(DateTime now) {
  final campus = now.toUtc().add(const Duration(hours: 8));
  return DateTime.utc(
        campus.year,
        campus.month,
        campus.day,
        -8,
      ).millisecondsSinceEpoch ~/
      1000;
}

/// 桌面组件共用的离线课表和校园日状态表。
final class ScheduleWidgetSnapshot {
  ScheduleWidgetSnapshot({
    required this.owner,
    required List<Map<String, Object?>> semesters,
    int? dayStart,
    this.upNext,
    this.today,
    this.todo,
  }) : dayStart = dayStart ?? widgetDayStart(DateTime.now()),
       semesters = List.unmodifiable(semesters);
  final int dayStart;
  final List<Map<String, Object?>>? upNext, today, todo;
  final String owner;
  final List<Map<String, Object?>> semesters;
  Map<String, Object?> toJson() {
    final data = <String, Object?>{
      'version': 2,
      'owner': owner,
      'semesters': semesters,
      'dayStart': dayStart,
      'horizonEnd': dayStart + 14 * 86400,
      'upNext': upNext,
      'today': today,
      'todo': todo,
    };
    if (utf8.encode(jsonEncode(data)).length > 1024 * 1024) {
      for (final table in ['upNext', 'today', 'todo']) {
        data[table] = null;
      }
    }
    return data;
  }

  @override
  String toString() => 'ScheduleWidgetSnapshot([REDACTED])';
}

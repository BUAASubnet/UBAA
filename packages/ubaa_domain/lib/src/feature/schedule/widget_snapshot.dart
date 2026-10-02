/// Android宿主可读的最小离线课表投影，不包含账号明文或写资格。
final class ScheduleWidgetSnapshot {
  ScheduleWidgetSnapshot({
    required this.owner,
    required List<Map<String, Object?>> semesters,
  }) : semesters = List.unmodifiable(semesters);
  final String owner;
  final List<Map<String, Object?>> semesters;
  Map<String, Object?> toJson() => {
    'version': 1,
    'owner': owner,
    'semesters': semesters,
  };
  @override
  String toString() => 'ScheduleWidgetSnapshot([REDACTED])';
}

import '../../common/error.dart';
import '../../common/cache_management.dart';
import '../../common/route.dart';

/// 完整读取与持久保存分别表达；中间进度不改变可见课表查询。
final class ScheduleImportProgress {
  const ScheduleImportProgress({
    required this.term,
    required this.completedWeeks,
    required this.totalWeeks,
    required this.finished,
    required this.route,
    this.saveFailure,
  });
  final String term;
  final int completedWeeks;
  final int? totalWeeks;
  final bool finished;
  final ConnectionMode route;
  final CacheMaintenanceFailure? saveFailure;
  bool get saved => finished && saveFailure == null;
}

enum ScheduleImportStatus { running, saved, cancelled, failed }

final class ScheduleImportState {
  const ScheduleImportState({required this.status, this.progress, this.error});
  final ScheduleImportStatus status;
  final ScheduleImportProgress? progress;
  final UiError? error;
}

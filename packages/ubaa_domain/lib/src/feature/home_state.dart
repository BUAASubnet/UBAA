import 'package:meta/meta.dart';
import 'catalog.dart';
import 'home.dart';
import 'result.dart';
import 'schedule/home.dart';

/// 首页已取得的内容与本轮更新状态。界面不拥有读取任务。
@immutable
final class HomeState {
  HomeState({
    required this.now,
    required Map<FeatureId, FeatureSnapshot> sources,
    required this.schedule,
    this.week,
    this.todos = const [],
    this.projected = false,
    this.projectionFailure,
    this.busy = false,
    this.refining = false,
    this.updatedAt,
  }) : sources = Map.unmodifiable(sources);
  final DateTime now;
  final Map<FeatureId, FeatureSnapshot> sources;
  final HomeScheduleState schedule;
  final FeatureResult? week;
  final List<HomeTodo> todos;
  final bool projected, busy, refining;
  final Object? projectionFailure;
  final DateTime? updatedAt;
}

@immutable
final class HomeScheduleState {
  const HomeScheduleState({
    required this.date,
    required this.snapshot,
    this.tomorrow = false,
    this.remote = false,
  });
  final String date;
  final FeatureSnapshot snapshot;
  final bool tomorrow, remote;
  DateTime get day => homeParseDate(date)!;
}

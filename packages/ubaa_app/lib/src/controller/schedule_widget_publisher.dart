import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

/// 同一宿主的组件发布协调器，账号变更先撤销旧原生发布代次。
final class ScheduleWidgetPublisher {
  ScheduleWidgetPublisher(this.gateway);
  final ScheduleWidgetGateway gateway;
  int _generation = 0;
  Future<void> _beginTail = Future.value();

  Future<void> update(
    String? owner,
    Future<ScheduleWidgetSnapshot> Function(bool Function()) read,
  ) async {
    final generation = ++_generation;
    final begin = _beginTail.then((_) => gateway.begin(owner));
    _beginTail = begin.then<void>((_) {}, onError: (Object _) {});
    final scope = await begin;
    bool current() => generation == _generation;
    if (!current() || owner == null) return;
    final snapshot = await read(current);
    if (!current() || snapshot.owner != owner) return;
    await gateway.publish(scope, snapshot);
  }

  void dispose() {
    _generation++;
  }
}

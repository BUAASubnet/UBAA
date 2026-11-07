import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/controller/home/coordinator.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

final now = DateTime.parse('2026-11-07T04:00:00Z');
void update(
  HomeCoordinator model, {
  int revision = 0,
  Object owner = 'account',
  bool online = false,
  bool readDays = false,
  Map<FeatureId, FeatureSnapshot>? sources,
}) => model.update(
  owner: owner,
  snapshots:
      sources ??
      {for (final f in FeatureId.values) f: FeatureSnapshot(feature: f)},
  epoch: 0,
  agenda: revision,
  active: true,
  online: online,
  blocked: false,
  foreground: false,
  readDays: readDays,
);
HomeTodo item(String title) => HomeTodo(
  id: 'exam:1',
  feature: FeatureId.exam,
  title: title,
  subtitle: '',
  statusLabel: '',
  timeLabel: '',
  sortTime: now,
);

void main() {
  test('内容相同的重新投影保留待办列表，刷新等待最新在途投影', () async {
    var calls = 0;
    final pending = Completer<HomeTodoProjection>();
    final model = HomeCoordinator(
      loadSupplement: (_, _) async => const FeatureResult.empty(),
      loadDay: (_, _) async => const FeatureResult.empty(),
      project: (_) => ++calls == 3
          ? pending.future
          : Future.value(HomeTodoProjection([item('相同内容')])),
      refreshMain: () async {},
      retryMain: (_) async {},
      changed: () {},
      now: () => now,
    );
    addTearDown(model.dispose);
    update(model);
    await model.flushProjection();
    final first = model.state.todos;
    update(model, revision: 1);
    await model.flushProjection();
    expect(identical(model.state.todos, first), isTrue);
    update(model, revision: 2);
    var finished = false;
    final flush = model.flushProjection().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    pending.complete(HomeTodoProjection([item('最新内容')]));
    await flush;
    expect(model.state.todos.single.title, '最新内容');
  });

  test('连续输入只保留一份在途投影与一份最新输入', () async {
    final gates = <Completer<HomeTodoProjection>>[];
    final model = HomeCoordinator(
      loadSupplement: (_, _) async => const FeatureResult.empty(),
      loadDay: (_, _) async => const FeatureResult.empty(),
      project: (_) {
        final gate = Completer<HomeTodoProjection>();
        gates.add(gate);
        return gate.future;
      },
      refreshMain: () async {},
      retryMain: (_) async {},
      changed: () {},
      now: () => now,
    );
    addTearDown(model.dispose);
    update(model);
    update(model, revision: 1);
    update(model, revision: 2);
    await Future<void>.delayed(Duration.zero);
    expect(gates, hasLength(1));
    update(model, revision: 3);
    update(model, revision: 4);
    await Future<void>.delayed(Duration.zero);
    expect(gates, hasLength(1));
    gates.first.complete(HomeTodoProjection([item('旧输入')]));
    await Future<void>.delayed(Duration.zero);
    expect(gates, hasLength(2));
    expect(model.state.todos, isEmpty);
    gates.last.complete(HomeTodoProjection([item('最新输入')]));
    await model.flushProjection();
    expect(model.state.todos.single.title, '最新输入');
  });

  test('展示日期课表仍在读取时刷新保持未完成', () async {
    final day = Completer<FeatureResult>();
    final model = HomeCoordinator(
      loadSupplement: (_, _) async => const FeatureResult.empty(),
      loadDay: (_, _) => day.future,
      project: (_) async => HomeTodoProjection([]),
      refreshMain: () async {},
      retryMain: (_) async {},
      changed: () {},
      now: () => now,
    );
    addTearDown(model.dispose);
    update(
      model,
      online: true,
      readDays: true,
      sources: {
        FeatureId.schedule: const FeatureSnapshot(
          feature: FeatureId.schedule,
          status: FeatureLoadStatus.empty,
        ),
      },
    );
    var finished = false;
    final refresh = model.refresh().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(model.state.schedule.date, '2026-11-08');
    expect(model.state.busy, isTrue);
    expect(finished, isFalse);
    day.complete(
      const FeatureResult.failure(
        UiError(
          code: UbaaErrorCode.networkError,
          title: '合成失败',
          message: '合成失败',
        ),
      ),
    );
    await refresh;
    await Future<void>.delayed(Duration.zero);
    expect(finished, isTrue);
    expect(model.state.busy, isFalse);
    expect(model.state.schedule.snapshot.status, FeatureLoadStatus.failure);
  });

  test('换账号时迟到投影不能恢复旧待办', () async {
    final old = Completer<HomeTodoProjection>();
    var reads = 0;
    final model = HomeCoordinator(
      loadSupplement: (_, _) async => const FeatureResult.empty(),
      loadDay: (_, _) async => const FeatureResult.empty(),
      project: (_) => ++reads == 1
          ? old.future
          : Future.value(HomeTodoProjection([item('新账号')])),
      refreshMain: () async {},
      retryMain: (_) async {},
      changed: () {},
      now: () => now,
    );
    addTearDown(model.dispose);
    update(model);
    await Future<void>.delayed(Duration.zero);
    update(model, owner: 'other');
    old.complete(HomeTodoProjection([item('旧账号')]));
    await Future<void>.delayed(Duration.zero);
    await model.flushProjection();
    expect(model.state.todos.single.title, '新账号');
  });
}

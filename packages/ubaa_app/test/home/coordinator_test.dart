import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/controller/home/coordinator.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

final now = DateTime.parse('2026-11-07T04:00:00Z');
void update(
  HomeCoordinator model, {
  int revision = 0,
  Object owner = 'account',
  Object? contentScope,
  bool online = false,
  bool blocked = false,
  bool readDays = false,
  int epoch = 0,
  Map<FeatureId, FeatureSnapshot>? sources,
}) => model.update(
  owner: owner,
  contentScope: contentScope,
  snapshots:
      sources ??
      {for (final f in FeatureId.values) f: FeatureSnapshot(feature: f)},
  epoch: epoch,
  agenda: revision,
  active: true,
  online: online,
  blocked: blocked,
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
  test('未注入时间时首页日期跟随可替换的时钟', () {
    final fixed = DateTime.parse('2026-09-21T01:30:00Z');
    final model = withClock(
      Clock.fixed(fixed),
      () => HomeCoordinator(
        loadSupplement: (_, _) async => const FeatureResult.empty(),
        loadDay: (_, _) async => const FeatureResult.empty(),
        project: (_) async => HomeTodoProjection(const []),
        refreshMain: () async {},
        retryMain: (_) async {},
        changed: () {},
      ),
    );
    addTearDown(model.dispose);
    expect(withClock(Clock.fixed(fixed), model.clock), fixed);
  });
  test('其他来源和本地日程更新期间保留签到操作，签到来源变化立即撤销', () async {
    const action = SigninPerformAction(
      scheduleId: 'synthetic-signin',
      eligibility: ActionEligibility.allowed,
    );
    final todo = HomeTodo(
      id: 'signin:1',
      feature: FeatureId.signin,
      title: '合成课程',
      subtitle: '',
      statusLabel: '',
      timeLabel: '',
      sortTime: now,
      signinAction: action,
    );
    Completer<HomeTodoProjection>? pending;
    final model = HomeCoordinator(
      loadSupplement: (_, _) async => const FeatureResult.empty(),
      loadDay: (_, _) async => const FeatureResult.empty(),
      project: (_) =>
          pending?.future ?? Future.value(HomeTodoProjection([todo])),
      refreshMain: () async {},
      retryMain: (_) async {},
      changed: () {},
      now: () => now,
    );
    addTearDown(model.dispose);
    const signin = FeatureSnapshot(
      feature: FeatureId.signin,
      status: FeatureLoadStatus.success,
    );
    final sources = <FeatureId, FeatureSnapshot>{FeatureId.signin: signin};
    update(model, sources: sources);
    await model.flushProjection();
    expect(model.state.todos.single.signinAction, same(action));

    pending = Completer<HomeTodoProjection>();
    sources[FeatureId.spoc] = const FeatureSnapshot(
      feature: FeatureId.spoc,
      status: FeatureLoadStatus.loading,
    );
    update(model, sources: sources, revision: 1);
    await Future<void>.delayed(Duration.zero);
    expect(model.state.todos.single.signinAction, same(action));
    pending.complete(HomeTodoProjection([todo]));
    await model.flushProjection();

    pending = Completer<HomeTodoProjection>();
    sources[FeatureId.signin] = signin.copyWith(
      status: FeatureLoadStatus.loading,
    );
    update(model, sources: sources, revision: 1);
    expect(model.state.todos.single.signinAction, isNull);
    pending.complete(HomeTodoProjection([todo.withoutSigninAction()]));
    await model.flushProjection();
    expect(model.state.todos.single.signinAction, isNull);

    pending = null;
    sources[FeatureId.signin] = signin;
    update(model, sources: sources, revision: 1);
    await model.flushProjection();
    expect(model.state.todos.single.signinAction, same(action));
    update(model, sources: sources, blocked: true);
    expect(model.state.todos.single.title, todo.title);
    expect(model.state.todos.single.signinAction, isNull);
    update(model, sources: sources);
    await model.flushProjection();
    pending = Completer<HomeTodoProjection>();
    update(model, sources: sources, epoch: 1);
    expect(model.state.todos.single.signinAction, isNull);
    update(
      model,
      sources: sources,
      owner: 'new-client',
      contentScope: 'account',
    );
    expect(model.state.todos.single.title, todo.title);
    expect(model.state.todos.single.signinAction, isNull);
    update(model, sources: sources, owner: 'other-account');
    expect(model.state.todos, isEmpty);
    pending.complete(HomeTodoProjection([]));
    await model.flushProjection();
  });

  test('全页刷新和联网失败始终保留预读的明日空课表', () async {
    final network = Completer<FeatureResult>();
    final cached = FeatureResult.empty(
      overview: const HomeScheduleOverview(
        date: '2026-11-08',
        week: WeekPresentation(
          requestTerm: 'term',
          responseTerm: 'term',
          number: 9,
          current: true,
          startDate: '2026-11-02',
          endDate: '2026-11-08',
        ),
      ),
      evidence: DataEvidence(
        accountId: 'account',
        origin: DataOrigin.persisted,
        fetchedAt: now,
        complete: true,
        savedForOffline: true,
      ),
    );
    final model = HomeCoordinator(
      loadSupplement: (_, _) async => const FeatureResult.empty(),
      readCachedDay: (_) async => cached,
      loadDay: (_, _) => network.future,
      project: (_) async => HomeTodoProjection([]),
      refreshMain: () async {},
      retryMain: (_) async {},
      changed: () {},
      now: () => now,
    );
    addTearDown(model.dispose);
    const sources = {
      FeatureId.schedule: FeatureSnapshot(
        feature: FeatureId.schedule,
        status: FeatureLoadStatus.empty,
      ),
    };
    update(model, readDays: true, sources: sources);
    await model.flushProjection();
    expect(model.state.schedule.snapshot.evidence, same(cached.evidence));
    update(model, readDays: true, online: true, epoch: 1, sources: sources);
    await Future<void>.delayed(Duration.zero);
    expect(model.state.schedule.snapshot.status, FeatureLoadStatus.loading);
    expect(model.state.schedule.snapshot.evidence, same(cached.evidence));
    network.complete(
      const FeatureResult.failure(
        UiError(code: UbaaErrorCode.networkError, title: '失败', message: '合成断网'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(model.state.schedule.snapshot.status, FeatureLoadStatus.stale);
    expect(model.state.schedule.snapshot.updatedAt, now);
    expect(model.state.schedule.snapshot.evidence, same(cached.evidence));
  });

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

  for (final fails in [false, true]) {
    test('明日课表先完成后，慢补充来源收尾不再次读取：失败=$fails', () async {
      var dayReads = 0;
      final supplement = Completer<FeatureResult>();
      late HomeCoordinator model;
      const sources = {
        FeatureId.schedule: FeatureSnapshot(
          feature: FeatureId.schedule,
          status: FeatureLoadStatus.empty,
        ),
      };
      model = HomeCoordinator(
        loadSupplement: (_, _) => supplement.future,
        loadDay: (date, force) async {
          dayReads++;
          return fails
              ? const FeatureResult.failure(
                  UiError(
                    code: UbaaErrorCode.networkError,
                    title: '合成失败',
                    message: '合成失败',
                  ),
                )
              : FeatureResult.empty(
                  overview: HomeScheduleOverview(
                    date: date,
                    week: const WeekPresentation(
                      requestTerm: 'term',
                      responseTerm: 'term',
                      number: 9,
                      current: true,
                      startDate: '2026-11-02',
                      endDate: '2026-11-08',
                    ),
                  ),
                );
        },
        project: (_) async => HomeTodoProjection([]),
        refreshMain: () async => update(
          model,
          online: true,
          readDays: true,
          epoch: 1,
          sources: sources,
        ),
        retryMain: (_) async {},
        changed: () {},
        now: () => now,
      );
      addTearDown(model.dispose);
      addTearDown(() {
        if (!supplement.isCompleted)
          supplement.complete(const FeatureResult.empty());
      });
      update(model, readDays: true, sources: sources);
      final refresh = model.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(dayReads, 1);
      supplement.complete(const FeatureResult.empty());
      await refresh;
      expect(dayReads, 1, reason: '本轮已尝试的日期在刷新收尾时直接复用');
    });
  }

  test('新一轮刷新不接受旧代次在途日期结果，下一轮仍会重新读取', () async {
    final oldDay = Completer<FeatureResult>();
    var reads = 0;
    var epoch = 0;
    late HomeCoordinator model;
    const sources = {
      FeatureId.schedule: FeatureSnapshot(
        feature: FeatureId.schedule,
        status: FeatureLoadStatus.empty,
      ),
    };
    const failure = FeatureResult.failure(
      UiError(code: UbaaErrorCode.networkError, title: '合成失败', message: '合成失败'),
    );
    model = HomeCoordinator(
      loadSupplement: (_, _) async => const FeatureResult.empty(),
      loadDay: (_, _) async => ++reads == 1 ? oldDay.future : failure,
      project: (_) async => HomeTodoProjection([]),
      refreshMain: () async => update(
        model,
        online: true,
        readDays: true,
        epoch: ++epoch,
        sources: sources,
      ),
      retryMain: (_) async {},
      changed: () {},
      now: () => now,
    );
    addTearDown(model.dispose);
    addTearDown(() {
      if (!oldDay.isCompleted) oldDay.complete(failure);
    });
    update(model, online: true, readDays: true, sources: sources);
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
    final refresh = model.refresh();
    oldDay.complete(failure);
    await refresh;
    expect(reads, 2);
    await model.refresh();
    expect(reads, 3);
  });

  test('补充来源等待期间另一轮读取推进代次，收尾仍等待新日期任务', () async {
    final supplement = Completer<FeatureResult>();
    final nextDay = Completer<FeatureResult>();
    var reads = 0;
    late HomeCoordinator model;
    const sources = {
      FeatureId.schedule: FeatureSnapshot(
        feature: FeatureId.schedule,
        status: FeatureLoadStatus.empty,
      ),
    };
    const failure = FeatureResult.failure(
      UiError(code: UbaaErrorCode.networkError, title: '合成失败', message: '合成失败'),
    );
    model = HomeCoordinator(
      loadSupplement: (_, _) => supplement.future,
      loadDay: (_, _) async => ++reads == 1 ? failure : nextDay.future,
      project: (_) async => HomeTodoProjection([]),
      refreshMain: () async => update(
        model,
        online: true,
        readDays: true,
        epoch: 1,
        sources: sources,
      ),
      retryMain: (_) async {},
      changed: () {},
      now: () => now,
    );
    addTearDown(model.dispose);
    addTearDown(() {
      if (!supplement.isCompleted)
        supplement.complete(const FeatureResult.empty());
      if (!nextDay.isCompleted) nextDay.complete(failure);
    });
    update(model, readDays: true, sources: sources);
    var finished = false;
    final refresh = model.refresh().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
    update(model, online: true, readDays: true, epoch: 2, sources: sources);
    await Future<void>.delayed(Duration.zero);
    expect(reads, 2);
    supplement.complete(const FeatureResult.empty());
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    nextDay.complete(failure);
    await refresh;
    expect(reads, 2);
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

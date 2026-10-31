import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import '../../support/controller/fakes.dart';

final _now = DateTime.parse('2026-11-01T12:00:00+08:00');
HomeTodoRequest _request(ConnectionMode route, {int revision = 0}) =>
    HomeTodoRequest(
      snapshots: {
        FeatureId.signin: FeatureSnapshot(
          feature: FeatureId.signin,
          status: FeatureLoadStatus.success,
          resolvedRoute: route,
          readContext: FeatureReadContext(requestRevision: revision),
          details: const [
            FeatureDetail(
              title: '合成签到',
              actions: [
                SigninPerformAction(
                  scheduleId: 'synthetic-target',
                  eligibility: ActionEligibility.allowed,
                ),
              ],
            ),
          ],
        ),
      },
      now: _now,
    );

Matcher _failure(AgendaFailure failure) =>
    throwsA(isA<AgendaException>().having((e) => e.failure, '投影失败类型', failure));

void main() {
  for (final (from, to) in [
    (RoutePolicy.direct, RoutePolicy.webvpn),
    (RoutePolicy.webvpn, RoutePolicy.direct),
    (RoutePolicy.direct, RoutePolicy.auto),
    (RoutePolicy.webvpn, RoutePolicy.auto),
    (RoutePolicy.auto, RoutePolicy.direct),
    (RoutePolicy.auto, RoutePolicy.webvpn),
  ]) {
    for (final fails in [false, true]) {
      test('$from→$to ${fails ? '回滚' : '成功'}：窗口内投影立即拒绝，收尾后恢复', () async {
        final backend = _Backend(from);
        final controller = AppController(backend: backend);
        addTearDown(controller.dispose);
        await controller.initialize();
        final gate = backend.delayNext();
        final switching = controller.setRoutePolicy(to);
        await gate.started.future;
        final sourceRoute = from == RoutePolicy.webvpn
            ? ConnectionMode.webvpn
            : ConnectionMode.direct;
        final calls = backend.received.length;
        // 先让纯投影结束，再结束切换，覆盖窗口内就交付旧动作的情况。
        backend.delayProjection = false;
        await expectLater(
          controller.projectHomeTodos(_request(sourceRoute)),
          _failure(AgendaFailure.unavailable),
        );
        expect(backend.received.length, calls);
        gate.finish(fails);
        await switching;
        final policy = fails ? from : to;
        expect(controller.loginForm.routePolicy, policy);
        final freshRoute = policy == RoutePolicy.webvpn
            ? ConnectionMode.webvpn
            : ConnectionMode.direct;
        await controller.retryFeature(FeatureId.signin);
        final fresh = controller.homeSnapshots[FeatureId.signin]!;
        expect(fresh.resolvedRoute, freshRoute);
        final result = await controller.projectHomeTodos(
          HomeTodoRequest(snapshots: {FeatureId.signin: fresh}, now: _now),
        );
        expect(result.todos.single.signinAction, isNotNull);
        // 新策略容许展示旧来源时，也只能保留只读内容，不能重新关联旧动作。
        final old = await controller.projectHomeTodos(_request(sourceRoute));
        expect(old.todos.every((todo) => todo.signinAction == null), isTrue);
      });
    }
  }

  test('路线切换窗口内启动且切换后完成的旧路线投影不能交付', () async {
    final backend = _Backend(RoutePolicy.direct);
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    final gate = backend.delayNext();
    final switching = controller.setRoutePolicy(RoutePolicy.webvpn);
    await gate.started.future;
    final projected = controller.projectHomeTodos(
      _request(ConnectionMode.direct),
    );
    final checked = expectLater(projected, throwsA(isA<AgendaException>()));
    gate.finish(false);
    await switching;
    backend.finishProjections();
    await checked;
  });

  test('已有投影先于切换，成功与失败都撤销旧读取代次', () async {
    for (final fails in [false, true]) {
      final backend = _Backend(RoutePolicy.direct);
      final controller = AppController(backend: backend);
      addTearDown(controller.dispose);
      await controller.initialize();
      final pending = controller.projectHomeTodos(
        _request(ConnectionMode.direct),
      );
      final checked = expectLater(pending, _failure(AgendaFailure.superseded));
      final gate = backend.delayNext();
      final switching = controller.setRoutePolicy(RoutePolicy.webvpn);
      await gate.started.future;
      backend.finishProjections();
      await checked;
      gate.finish(fails);
      await switching;
    }
  });

  test('快速切换的最后旧请求收尾也通知恢复，期间不交付任何投影', () async {
    final backend = _Backend(RoutePolicy.direct)..delayProjection = false;
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    final gate = backend.delayNext();
    final first = controller.setRoutePolicy(RoutePolicy.webvpn);
    await gate.started.future;
    await controller.setRoutePolicy(RoutePolicy.auto);
    await expectLater(
      controller.projectHomeTodos(_request(ConnectionMode.direct)),
      _failure(AgendaFailure.unavailable),
    );
    var notified = false;
    controller.addListener(() => notified = true);
    // 旧请求失败不能回滚新的 Auto，最后一项 transition 结束后必须通知首页。
    gate.finish(true);
    await first;
    expect(notified, isTrue);
    expect(controller.loginForm.routePolicy, RoutePolicy.auto);
    await controller.retryFeature(FeatureId.signin);
    final next = await controller.projectHomeTodos(
      HomeTodoRequest(snapshots: controller.homeSnapshots, now: _now),
    );
    expect(next.todos.single.signinAction, isNotNull);
  });

  test('投影中退出并以新账号登录，旧结果拒绝且账号不符来源不能进入新投影', () async {
    final backend = _Backend(RoutePolicy.direct);
    final accounts = await support.savedAccounts();
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final previousAccount = (await accounts.read())!.account!.id;
    final pending = controller.projectHomeTodos(
      _request(ConnectionMode.direct),
    );
    final checked = expectLater(pending, _failure(AgendaFailure.superseded));
    await controller.logout();
    controller.setUsername('synthetic-next');
    controller.setPassword('synthetic-password');
    await controller.submitLogin();
    backend.finishProjections();
    await checked;
    expect(controller.phase, AppPhase.home);
    expect(controller.user!.username, 'synthetic-next');
    expect((await accounts.read())!.account!.id, isNot(previousAccount));
    backend.delayProjection = false;
    final source = _request(ConnectionMode.direct).snapshots[FeatureId.signin]!;
    final next = await controller.projectHomeTodos(
      HomeTodoRequest(
        snapshots: {
          FeatureId.signin: source.copyWith(
            evidence: DataEvidence(
              accountId: 'synthetic-previous-account',
              origin: DataOrigin.online,
              fetchedAt: _now,
              complete: true,
              savedForOffline: false,
            ),
          ),
        },
        now: _now,
      ),
    );
    expect(next.todos, isEmpty);
    expect(backend.received.last.snapshots, isEmpty);
  });
}

class _RouteGate {
  final started = Completer<void>();
  final release = Completer<void>();
  void finish(bool fails) => fails
      ? release.completeError(
          const BackendException(UbaaErrorCode.internalError),
        )
      : release.complete();
}

class _Backend extends FixtureRouteStateBackend implements HomeTodoBackend {
  _Backend(RoutePolicy policy) : super(activeRoutes: ConnectionMode.values) {
    defaultPolicy = policy;
  }
  _RouteGate? gate;
  bool delayProjection = true;
  final received = <HomeTodoRequest>[];
  final pending = <Completer<HomeTodoProjection>>[];
  String username = 'fixture-user';
  @override
  Future<UserSummary?> userInfo() async => UserSummary(username: username);
  @override
  Future<void> login(LoginInput input) async => username = input.username;
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      feature == FeatureId.signin
      ? FeatureResult.success(
          details: _request(ConnectionMode.direct).snapshots[feature]!.details,
          resolvedRoute: defaultPolicy == RoutePolicy.webvpn
              ? ConnectionMode.webvpn
              : ConnectionMode.direct,
        )
      : const FeatureResult.empty();
  _RouteGate delayNext() => gate = _RouteGate();
  @override
  Future<void> prepareLogin(RoutePolicy policy) async {
    final waiting = gate;
    gate = null;
    if (waiting != null) {
      waiting.started.complete();
      await waiting.release.future;
    }
    defaultPolicy = policy;
  }

  @override
  Future<HomeTodoProjection> projectHomeTodos(HomeTodoRequest request) async {
    received.add(request);
    if (delayProjection) {
      final waiting = Completer<HomeTodoProjection>();
      pending.add(waiting);
      return waiting.future;
    }
    return HomeTodoProjection([
      for (final source in request.snapshots.values)
        for (final detail in source.details)
          HomeTodo(
            id: 'signin:synthetic',
            feature: FeatureId.signin,
            title: detail.title,
            subtitle: '',
            statusLabel: '状态待更新',
            timeLabel: '',
            sortTime: request.now,
            signinAction: detail.actions
                .whereType<SigninPerformAction>()
                .firstOrNull,
          ),
    ]);
  }

  void finishProjections() {
    for (final waiting in pending) {
      if (!waiting.isCompleted) waiting.complete(HomeTodoProjection(const []));
    }
  }
}

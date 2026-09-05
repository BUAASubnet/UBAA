import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('AppController 持有唯一写协调器并只转发一条状态通知', () async {
    final backend = _LifecycleBackend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    final coordinator = controller.writeCoordinator;
    expect(identical(coordinator, controller.writeCoordinator), isTrue);
    var notifications = 0;
    controller.addListener(() => notifications++);

    coordinator.setIntent(_intent('唯一实例'));

    expect(notifications, 1);
    expect(coordinator.intent?.intentId, '唯一实例');
    await coordinator.cancelForUi();
    expect(backend.discarded, <String>['唯一实例']);
  });

  test('注销开始即清除可提交意图，不等待 backend 注销完成', () async {
    final backend = _LifecycleBackend()..logoutGate = Completer<void>();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    final coordinator = controller.writeCoordinator;
    coordinator.setIntent(_intent('注销前'));

    final loggingOut = controller.logout();

    expect(coordinator.intent, isNull);
    expect(await coordinator.confirmForUi(), isNull);
    expect(backend.committed, isEmpty);
    backend.logoutGate!.complete();
    await loggingOut;
    expect(backend.discarded, <String>['注销前']);
  });

  test('同一路线保持待确认意图，真正切换前立即使其失效', () async {
    final backend = _LifecycleBackend()..routeGate = Completer<void>();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    final coordinator = controller.writeCoordinator;
    coordinator.setIntent(_intent('切换路线前'));

    await controller.setRoutePolicy(RoutePolicy.auto);
    expect(coordinator.intent?.intentId, '切换路线前');
    expect(backend.preparedRoutes, isEmpty);
    final switching = controller.setRoutePolicy(RoutePolicy.webvpn);

    expect(coordinator.intent, isNull);
    expect(await coordinator.confirmForUi(), isNull);
    expect(backend.committed, isEmpty);
    backend.routeGate!.complete();
    await switching;
    expect(backend.discarded, <String>['切换路线前']);
  });

  test('登录输入拒绝不影响意图，真正开始登录即使意图失效', () async {
    final backend = _LifecycleBackend()..loginGate = Completer<void>();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    final coordinator = controller.writeCoordinator;
    coordinator.setIntent(_intent('登录前'));

    await controller.submitLogin();
    expect(coordinator.intent?.intentId, '登录前');
    controller.setUsername('测试账号');
    controller.setPassword('仅用于确定性测试');
    final loggingIn = controller.submitLogin();

    expect(coordinator.intent, isNull);
    expect(await coordinator.confirmForUi(), isNull);
    expect(backend.committed, isEmpty);
    backend.loginGate!.complete();
    await loggingIn;
    expect(backend.discarded, <String>['登录前']);
  });

  test('初始化确认会话失效并进入登录页时清除待确认意图', () async {
    final backend = _LifecycleBackend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    final coordinator = controller.writeCoordinator;
    coordinator.setIntent(_intent('会话检查前'));

    await controller.initialize();

    expect(controller.phase, AppPhase.login);
    expect(coordinator.intent, isNull);
    expect(await coordinator.confirmForUi(), isNull);
    expect(backend.committed, isEmpty);
    expect(backend.discarded, <String>['会话检查前']);
  });

  for (final transition in <String>['注销', '切换路线']) {
    test('${transition}尚未完成且仍显示首页时拒绝新的准备和确认', () async {
      final gate = Completer<void>();
      final backend = _LifecycleBackend()..signedIn = true;
      final controller = AppController(backend: backend);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
        controller.dispose();
      });
      await controller.initialize();
      await Future<void>.delayed(Duration.zero);
      final coordinator = controller.writeCoordinator;
      final Future<void> changing;
      if (transition == '注销') {
        backend.logoutGate = gate;
        changing = controller.logout();
      } else {
        backend.routeGate = gate;
        changing = controller.setRoutePolicy(RoutePolicy.webvpn);
      }
      expect(controller.phase, AppPhase.home);
      var prepareCalls = 0;

      final prepared = await coordinator.prepareForUi(() async {
        prepareCalls++;
        return _intent('转换期间准备');
      }, expectedOperation: WriteOperation.bykcSelectCourse);
      coordinator.setIntent(_intent('转换期间确认'));
      final outcome = await coordinator.confirmForUi();

      expect(prepareCalls, 0);
      expect(prepared, isNull);
      expect(outcome, isNull);
      expect(backend.committed, isEmpty);
      gate.complete();
      await changing;
      expect(
        await coordinator.prepareForUi(
          () async => _intent('转换结束准备'),
          expectedOperation: WriteOperation.bykcSelectCourse,
        ),
        isNotNull,
      );
    });
  }

  for (final transition in <String>['注销', '切换路线', '登录', '重建']) {
    for (final command in <String>['准备', '确认']) {
      test('$transition 的同步状态通知禁止重入$command', () async {
        final gate = Completer<void>();
        final backend = _LifecycleBackend()..signedIn = true;
        final replacement = _LifecycleBackend();
        final controller = AppController(
          backend: backend,
          backendFactory: () => replacement,
        );
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
          controller.dispose();
        });
        await controller.initialize();
        await Future<void>.delayed(Duration.zero);
        controller.setUsername('测试账号');
        controller.setPassword('仅用于确定性测试');
        final coordinator = controller.writeCoordinator;
        coordinator.setIntent(_intent('转换之前'));
        var reentered = false;
        var prepareCalls = 0;
        Future<Object?>? attempted;
        controller.addListener(() {
          if (reentered) return;
          reentered = true;
          if (command == '准备') {
            attempted = coordinator.prepareForUi(() async {
              prepareCalls++;
              return _intent('通知重入准备');
            }, expectedOperation: WriteOperation.bykcSelectCourse);
          } else {
            coordinator.setIntent(_intent('通知重入确认'));
            attempted = coordinator.confirmForUi();
          }
        });
        final Future<Object?> changing;
        switch (transition) {
          case '注销':
            backend.logoutGate = gate;
            changing = controller.logout();
          case '切换路线':
            backend.routeGate = gate;
            changing = controller.setRoutePolicy(RoutePolicy.webvpn);
          case '登录':
            backend.loginGate = gate;
            changing = controller.submitLogin();
          case '重建':
            backend.disposeGate = gate;
            changing = controller.rebuildBackend();
          default:
            throw StateError('未知测试转换');
        }

        expect(reentered, isTrue);
        expect(await attempted, isNull);
        expect(prepareCalls, 0);
        expect(backend.committed, isEmpty);
        gate.complete();
        await changing;
      });
    }
  }

  test('路线切换与注销重叠时等待全部转换结束才恢复写入口', () async {
    final routeGate = Completer<void>();
    final logoutGate = Completer<void>();
    final backend = _LifecycleBackend()
      ..routeGate = routeGate
      ..logoutGate = logoutGate;
    final controller = AppController(backend: backend);
    addTearDown(() {
      if (!routeGate.isCompleted) routeGate.complete();
      if (!logoutGate.isCompleted) logoutGate.complete();
      controller.dispose();
    });
    final changingRoute = controller.setRoutePolicy(RoutePolicy.webvpn);
    final loggingOut = controller.logout();
    routeGate.complete();
    await changingRoute;
    var prepareCalls = 0;

    final prepared = await controller.writeCoordinator.prepareForUi(() async {
      prepareCalls++;
      return _intent('重叠转换期间');
    }, expectedOperation: WriteOperation.bykcSelectCourse);

    expect(prepared, isNull);
    expect(prepareCalls, 0);
    logoutGate.complete();
    await loggingOut;
    expect(
      await controller.writeCoordinator.prepareForUi(
        () async => _intent('全部转换结束'),
        expectedOperation: WriteOperation.bykcSelectCourse,
      ),
      isNotNull,
    );
  });

  test('重建期间晚到 prepare 只向原 backend 释放，新协调器使用新 backend', () async {
    final first = _LifecycleBackend()..prepareGate = Completer<WriteIntent>();
    final replacement = _LifecycleBackend();
    final controller = AppController(
      backend: first,
      backendFactory: () => replacement,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final previous = controller.writeCoordinator;
    final preparing = previous.prepareForUi(
      () => controller.prepareBykcWrite(WriteOperation.bykcSelectCourse, 1),
      expectedOperation: WriteOperation.bykcSelectCourse,
    );

    expect(await controller.rebuildBackend(), isTrue);
    final current = controller.writeCoordinator;
    expect(identical(previous, current), isFalse);
    var notifications = 0;
    controller.addListener(() => notifications++);
    first.prepareGate!.complete(_intent('旧准备结果'));

    expect(await preparing, isNull);
    expect(first.discarded, <String>['旧准备结果']);
    expect(replacement.discarded, isEmpty);
    expect(notifications, 0);
    previous.setIntent(_intent('旧实例不可复用'));
    expect(previous.intent, isNull);
    expect(notifications, 0);
    current.setIntent(_intent('新实例确认'));
    expect(notifications, 1);
    final result = await current.confirmForUi();
    expect(result?.result?.success, isTrue);
    expect(first.committed, isEmpty);
    expect(replacement.committed, <String>['新实例确认']);
    expect(first.disposeCalls, 1);
  });

  test('旧提交在 backend 重建后完成时不向新会话回读或交付结果', () async {
    final first = _LifecycleBackend()
      ..commitGate = Completer<WriteCommitResult>();
    final replacement = _LifecycleBackend();
    final controller = AppController(
      backend: first,
      backendFactory: () => replacement,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final previous = controller.writeCoordinator;
    previous.setIntent(_intent('在途提交'));
    final confirming = previous.confirmForUi();
    expect(first.committed, <String>['在途提交']);

    expect(await controller.rebuildBackend(), isTrue);
    first.commitGate!.complete(_success());

    expect(await confirming, isNull);
    expect(first.loaded, isEmpty);
    expect(replacement.loaded, isEmpty);
    expect(replacement.committed, isEmpty);
  });

  for (final transition in <String>['注销', '切换路线', '登录']) {
    test('$transition 使已经开始的写后回读失效且旧结果不覆盖快照', () async {
      final backend = _LifecycleBackend()
        ..readGate = Completer<FeatureResult>();
      final controller = AppController(backend: backend);
      addTearDown(controller.dispose);
      final coordinator = controller.writeCoordinator;
      coordinator.setIntent(_intent('回读中'));
      final confirming = coordinator.confirmForUi();
      await backend.readStarted.future;

      Future<void>? loggingIn;
      switch (transition) {
        case '注销':
          await controller.logout();
        case '切换路线':
          await controller.setRoutePolicy(RoutePolicy.webvpn);
        case '登录':
          backend.loginGate = Completer<void>();
          controller.setUsername('测试账号');
          controller.setPassword('仅用于确定性测试');
          loggingIn = controller.submitLogin();
      }
      backend.readGate!.complete(const FeatureResult.success(summary: '旧会话结果'));

      expect(await confirming, isNull);
      expect(controller.snapshots[FeatureId.bykc]!.summary, isNot('旧会话结果'));
      if (loggingIn != null) {
        backend.loginGate!.complete();
        await loggingIn;
      }
    });
  }

  for (final transition in <String>['注销', '切换路线']) {
    test('场馆取消列表读取期间${transition}后不继续请求订单详情', () async {
      final backend = _CgyyLifecycleBackend();
      final controller = AppController(backend: backend);
      addTearDown(controller.dispose);
      final verifying = controller.verifyCgyyCancellation(
        orderId: 12,
        expectedRoute: ConnectionMode.direct,
      );
      await backend.ordersStarted.future;

      if (transition == '注销') {
        await controller.logout();
      } else {
        await controller.setRoutePolicy(RoutePolicy.webvpn);
      }
      backend.ordersGate.complete(
        const FeatureResult.empty(resolvedRoute: ConnectionMode.direct),
      );

      expect(await verifying, isFalse);
      expect(backend.detailCalls, 0);
    });
  }

  test('销毁和重建交错时 backend 只释放一次，晚到 prepare 无通知', () async {
    final first = _LifecycleBackend()
      ..prepareGate = Completer<WriteIntent>()
      ..disposeGate = Completer<void>();
    final replacement = _LifecycleBackend();
    final controller = AppController(
      backend: first,
      backendFactory: () => replacement,
    );
    await controller.initialize();
    final coordinator = controller.writeCoordinator;
    final preparing = coordinator.prepareForUi(
      () => controller.prepareBykcWrite(WriteOperation.bykcSelectCourse, 1),
      expectedOperation: WriteOperation.bykcSelectCourse,
    );
    final rebuilding = controller.rebuildBackend();
    await first.disposeStarted.future;
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.dispose();
    controller.dispose();
    first.prepareGate!.complete(_intent('销毁后准备结果'));

    expect(await preparing, isNull);
    expect(notifications, 0);
    expect(first.discarded, <String>['销毁后准备结果']);
    expect(first.disposeCalls, 1);
    first.disposeGate!.complete();
    expect(await rebuilding, isFalse);
    expect(first.disposeCalls, 1);
    expect(replacement.disposeCalls, 1);
    expect(notifications, 0);
  });
}

WriteIntent _intent(String id) => WriteIntent(
  intentId: id,
  operation: WriteOperation.bykcSelectCourse,
  targetSummary: '测试博雅课程',
  resolvedRoute: ConnectionMode.direct,
  warnings: const <String>[],
  expiresAt: DateTime.now().add(const Duration(minutes: 2)),
  requestDigest: '测试摘要',
);

WriteCommitResult _success() => const WriteCommitResult(
  operation: WriteOperation.bykcSelectCourse,
  success: true,
  message: '已提交',
  outcomeUnknown: false,
);

class _LifecycleBackend
    implements UbaaBackend, BykcWriteBackend, BackendLifecycle {
  bool signedIn = false;
  Completer<WriteIntent>? prepareGate;
  Completer<WriteCommitResult>? commitGate;
  Completer<FeatureResult>? readGate;
  Completer<void>? routeGate;
  Completer<void>? loginGate;
  Completer<void>? logoutGate;
  Completer<void>? disposeGate;
  final readStarted = Completer<void>();
  final disposeStarted = Completer<void>();
  final preparedRoutes = <RoutePolicy>[];
  final discarded = <String>[];
  final committed = <String>[];
  final loaded = <FeatureId>[];
  int disposeCalls = 0;

  @override
  Future<AuthStatus> authStatus() async =>
      signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async =>
      signedIn ? const UserSummary(username: '测试账号') : null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {
    preparedRoutes.add(policy);
    await routeGate?.future;
  }

  @override
  Future<void> login(LoginInput input) async => await loginGate?.future;

  @override
  Future<void> logout() async => await logoutGate?.future;

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    loaded.add(feature);
    if (feature == FeatureId.bykc && readGate != null) {
      if (!readStarted.isCompleted) readStarted.complete();
      return readGate!.future;
    }
    return const FeatureResult.empty();
  }

  @override
  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) async =>
      prepareGate?.future ?? _intent('准备结果');

  @override
  Future<WriteIntent> prepareBykcDeselectCourse({
    required int courseId,
  }) async => _intent('退课准备结果');

  @override
  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) async => _intent('签到准备结果');

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    committed.add(intentId);
    return commitGate?.future ?? _success();
  }

  @override
  Future<void> discardWriteIntent(String intentId) async =>
      discarded.add(intentId);

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (!disposeStarted.isCompleted) disposeStarted.complete();
    await disposeGate?.future;
  }
}

class _CgyyLifecycleBackend extends _LifecycleBackend
    implements CgyyCancellationReadbackBackend {
  final ordersStarted = Completer<void>();
  final ordersGate = Completer<FeatureResult>();
  int detailCalls = 0;

  @override
  Future<FeatureResult> loadCgyyOrdersOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) {
    ordersStarted.complete();
    return ordersGate.future;
  }

  @override
  Future<FeatureResult> loadCgyyOrderDetailOnRoute({
    required ConnectionMode route,
    required int orderId,
  }) async {
    detailCalls++;
    return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
  }
}

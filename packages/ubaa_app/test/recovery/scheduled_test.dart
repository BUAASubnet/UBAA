import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/recovery.dart' as support;

Future<void> until(
  AppController controller,
  _Backend backend,
  bool Function() ready,
) async {
  final done = Completer<void>();
  void observe() {
    if (ready() && !done.isCompleted) done.complete();
  }

  controller.addListener(observe);
  final subscription = backend.changed.stream.listen((_) => observe());
  try {
    observe();
    await done.future;
  } finally {
    controller.removeListener(observe);
    await subscription.cancel();
  }
}

void main() {
  for (final route in [ConnectionMode.direct, ConnectionMode.webvpn]) {
    test('其他领域登录后只重建相同路线计划：${route.name}', () async {
      final backend = _PausedBackend(route);
      final controller = AppController(
        backend: backend,
        localAccountStore: await support.savedAccounts(),
        credentialVault: MemoryCredentialVault(
          initial: const Credential(
            username: 'fixture-user',
            password: 'synthetic',
            autoLogin: true,
          ),
        ),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.recoverSession();
      await until(
        controller,
        backend,
        () => backend.tasks.isNotEmpty && backend.tasks.first.calls == 2,
      );
      backend.missing.add(FeatureId.signin);
      await controller.recoverSession(
        feature: FeatureId.signin,
        refreshHomeAfter: false,
      );
      expect(
        controller.homeSnapshots[FeatureId.judge]!.details.single.title,
        '已显示内容',
      );
      expect(backend.tasks.first.cancelled, route == ConnectionMode.webvpn);
      backend.gate.complete();
      await until(
        controller,
        backend,
        () =>
            controller.homeSnapshots[FeatureId.judge]!.status !=
            FeatureLoadStatus.loading,
      );
      expect(backend.tasks.length, route == ConnectionMode.webvpn ? 2 : 1);
      expect(
        controller.homeSnapshots[FeatureId.judge]!.details.single.title,
        route == ConnectionMode.webvpn ? '新计划内容' : '原计划完成',
      );
    });
  }
  for (final preparing in [false, true]) {
    test('并行读取组在其他路线登录后重新准备，准备中=$preparing', () async {
      final backend = _PoolBackend(preparing: preparing);
      final controller = AppController(
        backend: backend,
        localAccountStore: await support.savedAccounts(),
        credentialVault: MemoryCredentialVault(
          initial: const Credential(
            username: 'fixture-user',
            password: 'synthetic',
            autoLogin: true,
          ),
        ),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.recoverSession();
      await until(
        controller,
        backend,
        () =>
            backend.tasks.isNotEmpty &&
            (preparing || backend.tasks.first.calls == 2),
      );
      backend.missing.add(FeatureId.signin);
      await controller.recoverSession(
        feature: FeatureId.signin,
        refreshHomeAfter: false,
      );
      backend.gate.complete();
      await until(
        controller,
        backend,
        () =>
            controller.homeSnapshots[FeatureId.judge]!.status !=
            FeatureLoadStatus.loading,
      );
      final snapshot = controller.homeSnapshots[FeatureId.judge]!;
      expect(snapshot.error, isNull);
      expect(snapshot.details.single.title, '新计划内容');
      expect(backend.tasks, hasLength(2));
      expect(backend.tasks.first.cancelled, isTrue);
      expect(backend.logins, [ConnectionMode.webvpn]);
    });
  }

  test('同一读取先后遇到两个已核验登录时分别重新准备', () async {
    final backend = _RevisionBackend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: 'fixture-user',
          password: 'synthetic',
          autoLogin: true,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    for (var revision = 0; revision < 2; revision++) {
      await until(
        controller,
        backend,
        () =>
            backend.tasks.length > revision &&
            backend.tasks[revision].calls == 2,
      );
      final feature = revision == 0 ? FeatureId.signin : FeatureId.cgyy;
      backend.missing.add(feature);
      await controller.recoverSession(
        feature: feature,
        refreshHomeAfter: false,
      );
      backend.gates[revision].complete();
    }
    await until(
      controller,
      backend,
      () =>
          controller.homeSnapshots[FeatureId.judge]!.status !=
          FeatureLoadStatus.loading,
    );
    final snapshot = controller.homeSnapshots[FeatureId.judge]!;
    expect(snapshot.error, isNull);
    expect(snapshot.details.single.title, '修订2结果');
    expect(backend.tasks, hasLength(3));
    expect(backend.logins, [ConnectionMode.webvpn, ConnectionMode.webvpn]);
  });

  for (final mismatch in [false, true]) {
    test('没有已知登录替换时不重试${mismatch ? '异账号' : '操作冲突'}', () async {
      final backend = _ConflictBackend(mismatch);
      final controller = AppController(
        backend: backend,
        localAccountStore: await support.savedAccounts(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.recoverSession(refreshHomeAfter: false);
      await controller.refreshHome(only: [FeatureId.judge]);
      expect(backend.started, 1);
      expect(backend.logins, isEmpty);
      expect(controller.homeSnapshots[FeatureId.judge]!.details, isEmpty);
      if (mismatch) {
        expect(controller.phase, AppPhase.login);
        expect(controller.cacheAccountId, isNull);
      } else {
        expect(
          controller.homeSnapshots[FeatureId.judge]!.error?.code,
          UbaaErrorCode.operationConflict,
        );
      }
    });
  }

  test('真实路线切换丢弃准备中的旧计划且不自动重建', () async {
    final backend = _RoutePoolBackend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    await until(controller, backend, () => backend.tasks.isNotEmpty);
    await controller.setRoutePolicy(RoutePolicy.webvpn);
    backend.gate.complete();
    await until(controller, backend, () => backend.tasks.first.cancelled);
    expect(backend.tasks, hasLength(1));
    expect(backend.logins, isEmpty);
    expect(controller.homeSnapshots[FeatureId.judge]!.details, isEmpty);
  });

  test('预约辅助查询先恢复自己的路线且不被恢复过程误取消', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(refreshHomeAfter: false);
    final result = await controller.loadCgyyPurposes();
    expect(result.error, isNull);
    expect(
      backend.events.indexOf('auth:cgyy'),
      lessThan(backend.events.indexOf('read:cgyy')),
    );
    expect(backend.events, contains('read:cgyy'));
  });

  for (final persistentFailure in [false, true]) {
    test('分段认证失效只重建一次读取计划，持续失效=$persistentFailure', () async {
      final backend = _ExpiringBackend(persistentFailure);
      final controller = AppController(
        backend: backend,
        localAccountStore: await support.savedAccounts(),
        credentialVault: MemoryCredentialVault(
          initial: const Credential(
            username: 'fixture-user',
            password: 'synthetic',
            autoLogin: true,
          ),
        ),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.recoverSession();
      await until(controller, backend, () => backend.tasks.length == 2);
      await until(
        controller,
        backend,
        () =>
            controller.homeSnapshots[FeatureId.judge]!.status !=
            FeatureLoadStatus.loading,
      );
      expect(backend.tasks.length, 2);
      expect(backend.tasks.every((task) => task.cancelled), isTrue);
      expect(backend.logins, [ConnectionMode.webvpn]);
      final snapshot = controller.homeSnapshots[FeatureId.judge]!;
      if (persistentFailure) {
        expect(snapshot.error, isNotNull);
      } else {
        expect(snapshot.error, isNull);
        expect(snapshot.details.single.title, '恢复后结果');
      }
    });
  }

  test('首页先读已恢复课表，其他领域在自己的执行边界恢复所需路线', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    await until(
      controller,
      backend,
      () => backend.events.contains('read:ygdk'),
    );
    expect(
      backend.events.indexOf('read:schedule'),
      lessThan(backend.events.indexOf('auth:signin')),
    );
    for (final feature in [
      FeatureId.signin,
      FeatureId.spoc,
      FeatureId.judge,
      FeatureId.ygdk,
    ]) {
      expect(
        backend.events.indexOf('auth:${feature.name}'),
        greaterThanOrEqualTo(0),
      );
      expect(
        backend.events.indexOf('auth:${feature.name}'),
        lessThan(backend.events.indexOf('read:${feature.name}')),
      );
    }
    expect(backend.legacyAuth, 0);
  });
  test('后台路线缺材料只影响该领域，已就绪路线仍能继续读取', () async {
    final backend = _Backend()..missing.add(FeatureId.judge);
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    await until(
      controller,
      backend,
      () => controller.snapshots[FeatureId.judge]!.error != null,
    );
    expect(backend.events, isNot(contains('read:judge')));
    await controller.refreshHome(only: [FeatureId.schedule]);
    expect(
      controller.homeSnapshots[FeatureId.schedule]!.status,
      FeatureLoadStatus.success,
    );
    expect(backend.logins, isEmpty);
  });
  test('后台目标失效后只向 Core 返回的路线提交获准凭据', () async {
    final backend = _Backend()..missing.add(FeatureId.judge);
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: 'fixture-user',
          password: 'synthetic',
          autoLogin: true,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    await until(
      controller,
      backend,
      () => backend.events.contains('read:judge'),
    );
    expect(backend.logins, [ConnectionMode.webvpn]);
    expect(controller.homeSnapshots[FeatureId.judge]!.error, isNull);
  });
}

class _Backend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        ProgressiveReadBackend,
        RequiredSessionBackend {
  final changed = StreamController<void>.broadcast(sync: true);
  void signal() => changed.add(null);
  final events = <String>[];
  final missing = <FeatureId>{};
  final logins = <ConnectionMode>[];
  int legacyAuth = 0;
  @override
  Future<AuthStatus> authStatus() async {
    legacyAuth++;
    return AuthStatus.signedIn;
  }

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'fixture-user');
  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    events.add('auth:${feature.name}');
    signal();
    if (missing.contains(feature))
      throw const BackendException(
        UbaaErrorCode.authenticationRequired,
        resolvedRoute: ConnectionMode.webvpn,
      );
    return const RecoveredRouteSession(
      route: ConnectionMode.direct,
      profile: UserSummary(username: 'fixture-user'),
    );
  }

  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) async {
    logins.add(route);
    missing.clear();
    return RecoveredRouteSession(
      route: route,
      profile: const UserSummary(username: 'fixture-user'),
    );
  }

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    events.add('read:${feature.name}');
    signal();
    return FeatureResult.success(summary: feature.name);
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) => loadFeature(feature);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ExpiringBackend extends _Backend {
  _ExpiringBackend(this.persistentFailure);
  final bool persistentFailure;
  final tasks = <_ExpiringTask>[];
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async {
    if (feature != FeatureId.judge) return null;
    final task = _ExpiringTask(this, tasks.isEmpty || persistentFailure);
    tasks.add(task);
    signal();
    return task;
  }
}

class _ExpiringTask implements FeatureReadTask {
  _ExpiringTask(this.backend, this.expire);
  final _ExpiringBackend backend;
  final bool expire;
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
  @override
  Future<FeatureReadBatch> next() async {
    if (expire) {
      backend.missing.add(FeatureId.judge);
      throw const BackendException(
        UbaaErrorCode.authenticationRequired,
        resolvedRoute: ConnectionMode.webvpn,
      );
    }
    return const FeatureReadBatch(
      FeatureResult.success(
        details: [FeatureDetail(title: '恢复后结果')],
        resolvedRoute: ConnectionMode.webvpn,
      ),
      finished: true,
    );
  }
}

class _PausedBackend extends _Backend {
  _PausedBackend(this.route);
  final ConnectionMode route;
  final gate = Completer<void>();
  final tasks = <_PausedTask>[];
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async {
    if (feature != FeatureId.judge) return null;
    final task = _PausedTask(this, tasks.isNotEmpty);
    tasks.add(task);
    signal();
    return task;
  }
}

class _PausedTask implements FeatureReadTask {
  _PausedTask(this.backend, this.restarted);
  final _PausedBackend backend;
  final bool restarted;
  int calls = 0;
  bool cancelled = false;
  @override
  void cancel() {
    cancelled = true;
    backend.signal();
  }

  @override
  Future<FeatureReadBatch> next() async {
    calls++;
    backend.signal();
    if (!restarted && calls == 2) await backend.gate.future;
    if (!restarted && backend is _PoolBackend && backend.logins.isNotEmpty) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    return FeatureReadBatch(
      FeatureResult.success(
        details: [
          FeatureDetail(
            title: restarted
                ? '新计划内容'
                : calls == 1
                ? '已显示内容'
                : '原计划完成',
          ),
        ],
        resolvedRoute: backend.route,
      ),
      finished: restarted || calls == 2,
    );
  }
}

// 生产读取池的任一路线登录都会替换双路线 worker，旧计划随之失效。
class _PoolBackend extends _PausedBackend implements ConcurrentReadBackend {
  _PoolBackend({required this.preparing}) : super(ConnectionMode.direct);
  final bool preparing;
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async {
    final task = await super.beginFeatureRead(feature, query);
    if (task != null && preparing && tasks.length == 1) {
      await gate.future;
    }
    return task;
  }
}

class _RevisionBackend extends _Backend implements ConcurrentReadBackend {
  final tasks = <_RevisionTask>[];
  final gates = [Completer<void>(), Completer<void>()];
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async {
    if (feature != FeatureId.judge) return null;
    final task = _RevisionTask(this, logins.length);
    tasks.add(task);
    signal();
    return task;
  }
}

class _RevisionTask implements FeatureReadTask {
  _RevisionTask(this.backend, this.revision);
  final _RevisionBackend backend;
  final int revision;
  int calls = 0;
  @override
  void cancel() {}
  @override
  Future<FeatureReadBatch> next() async {
    calls++;
    backend.signal();
    if (revision < 2 && calls == 2) await backend.gates[revision].future;
    if (revision != backend.logins.length) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    return FeatureReadBatch(
      FeatureResult.success(
        details: [FeatureDetail(title: '修订$revision结果')],
        resolvedRoute: ConnectionMode.webvpn,
      ),
      finished: revision == 2,
    );
  }
}

class _ConflictBackend extends _Backend implements ConcurrentReadBackend {
  _ConflictBackend(this.mismatch);
  final bool mismatch;
  int started = 0;
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async {
    if (feature != FeatureId.judge) return null;
    started++;
    throw BackendException(
      mismatch
          ? UbaaErrorCode.authenticationRequired
          : UbaaErrorCode.operationConflict,
      accountMismatch: mismatch,
    );
  }
}

class _RoutePoolBackend extends _PoolBackend implements RouteSettingsBackend {
  _RoutePoolBackend() : super(preparing: true);
  RoutePolicy policy = RoutePolicy.direct;
  @override
  Future<void> prepareLogin(RoutePolicy value) async => policy = value;
  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: policy,
    activeRoutes: ConnectionMode.values,
  );
}

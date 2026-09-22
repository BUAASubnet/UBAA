import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../startup_test.dart' as support;
import '../query_cache_test.dart' show until;

void main() {
  test('清理期间已打开的旧首页读取不重试并复活已清内容', () async {
    final store = _DelayedStore(await support.savedAccounts())..gate.complete();
    final backend = _ManagedBackend()..readGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: store,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await until(() => backend.policies.isNotEmpty);
    await controller.clearBusinessCache(accountId: backend.account!.id);
    backend.readGate!.complete();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.homeSnapshots[FeatureId.schedule]!.details, isEmpty);
    expect(backend.policies, hasLength(1));
  });

  test('同账号重新登录后旧打开任务不能复活', () async {
    final store = _DelayedStore(await support.savedAccounts());
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: store,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.logout();
    controller.setUsername('fixture-user');
    controller.setPassword('synthetic-password');
    await controller.submitLogin();
    expect(backend.opens, 1);
    store.gate.complete();
    await until(() => store.key.every((value) => value == 0));
    expect(backend.opens, 1);
    expect(controller.phase, AppPhase.home);
  });

  test('销毁后迟到密钥不再打开仓库', () async {
    final store = _DelayedStore(await support.savedAccounts());
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: store,
    );
    await controller.initialize();
    controller.dispose();
    store.gate.complete();
    await until(() => store.key.every((value) => value == 0));
    expect(backend.opens, 0);
  });

  test('密钥尚未返回时切路线仍打开同一账号并读取新路线首页', () async {
    final store = _DelayedStore(await support.savedAccounts());
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: store,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.setRoutePolicy(RoutePolicy.webvpn);
    store.gate.complete();
    await until(() => backend.opens == 1);
    await until(
      () => controller.homeSnapshots[FeatureId.schedule]!.details.isNotEmpty,
    );
    expect(backend.policies, [RoutePolicy.webvpn]);
    expect(
      controller.homeSnapshots[FeatureId.schedule]!.resolvedRoute,
      ConnectionMode.webvpn,
    );
    expect(store.key, everyElement(0));
    expect(backend.authCalls, 0);
  });

  test('磁盘投影挂起时换路线丢弃旧结果并重读新范围', () async {
    final store = _DelayedStore(await support.savedAccounts())..gate.complete();
    final backend = _Backend()..readGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: store,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await until(() => backend.policies.isNotEmpty);
    await controller.setRoutePolicy(RoutePolicy.webvpn);
    backend.readGate!.complete();
    await until(() => backend.policies.length == 2);
    await until(
      () => controller.homeSnapshots[FeatureId.schedule]!.details.isNotEmpty,
    );
    expect(
      controller.homeSnapshots[FeatureId.schedule]!.resolvedRoute,
      ConnectionMode.webvpn,
    );
    expect(backend.opens, 1);
  });

  test('退出后的迟到密钥不能打开旧账号且仍清零', () async {
    final store = _DelayedStore(await support.savedAccounts());
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: store,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.logout();
    store.gate.complete();
    await until(() => store.key.every((value) => value == 0));
    expect(backend.opens, 0);
    expect(controller.homeSnapshots[FeatureId.schedule]!.details, isEmpty);
  });
}

class _DelayedStore implements LocalAccountStore {
  _DelayedStore(this.delegate);
  final LocalAccountStore delegate;
  final gate = Completer<void>();
  int keyCalls = 0;
  final key = Uint8List.fromList(List.filled(32, 7));
  @override
  Future<Uint8List> cacheKey(LocalAccount account) async {
    if (++keyCalls > 1) return Uint8List.fromList(List.filled(32, 7));
    await gate.future;
    return key;
  }

  @override
  Future<LocalAccountState?> read() => delegate.read();
  @override
  Future<LocalAccountState> retain(
    String username, {
    required bool retainSession,
  }) => delegate.retain(username, retainSession: retainSession);
  @override
  Future<void> signOut() => delegate.signOut();
  @override
  Future<void> removeAccount(String id) => delegate.removeAccount(id);
}

class _Backend extends support.FakeRecoveryBackend
    implements OfflineCacheBackend {
  LocalAccount? account;
  int opens = 0;
  Completer<void>? readGate;
  final policies = <RoutePolicy>[];
  @override
  Future<void> openOfflineAccount(LocalAccount value, List<int> key) async {
    account = value;
    opens++;
  }

  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) async {
    policies.add(policy);
    await readGate?.future;
    return OfflineHomeRead([
      CachedFeatureProjection(
        feature: FeatureId.schedule,
        accountId: account!.id,
        route: policy == RoutePolicy.webvpn
            ? ConnectionMode.webvpn
            : ConnectionMode.direct,
        fetchedAt: DateTime.utc(2026, 9, 1),
        complete: true,
        details: const [FeatureDetail(title: '合成课表')],
      ),
    ]);
  }

  @override
  Future<void> deactivateOfflineAccount() async {}
  @override
  Future<void> clearOfflineAccount() async {}
}

class _ManagedBackend extends _Backend implements CacheManagementBackend {
  @override
  Future<CacheClearOutcome> clearBusinessCache({
    required String accountId,
  }) async => const CacheClearOutcome(compacted: true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

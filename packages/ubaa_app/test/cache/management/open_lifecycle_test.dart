import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import '../../support/controller/clock_accounts.dart';
import '../query_test.dart' show until;

void main() {
  testWidgets('清理期间已打开的旧首页读取不重试并复活已清内容', (tester) async {
    final store = _DelayedStore(ClockAccounts())..gate.complete();
    final backend = _ManagedBackend()..readGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: store,
    );
    addTearDown(controller.dispose);
    await _initialize(tester, controller);
    expect(backend.policies, hasLength(1));
    await controller.clearBusinessCache(accountId: backend.account!.id);
    backend.readGate!.complete();
    await tester.pump();
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

  testWidgets('销毁后迟到密钥不再打开仓库', (tester) async {
    final store = _DelayedStore(ClockAccounts());
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: store,
    );
    await _initialize(tester, controller);
    controller.dispose();
    store.gate.complete();
    await tester.pump();
    expect(store.key, everyElement(0));
    expect(backend.opens, 0);
  });

  testWidgets('密钥尚未返回时切路线仍打开同一账号并读取新路线首页', (tester) async {
    final store = _DelayedStore(ClockAccounts());
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: store,
    );
    addTearDown(controller.dispose);
    await _initialize(tester, controller);
    await controller.setRoutePolicy(RoutePolicy.webvpn);
    store.gate.complete();
    await tester.pump();
    expect(backend.opens, 1);
    expect(controller.homeSnapshots[FeatureId.schedule]!.details, isNotEmpty);
    expect(backend.policies, [RoutePolicy.webvpn]);
    expect(
      controller.homeSnapshots[FeatureId.schedule]!.resolvedRoute,
      ConnectionMode.webvpn,
    );
    expect(store.key, everyElement(0));
    expect(backend.authCalls, 0);
  });

  testWidgets('磁盘投影挂起时换路线丢弃旧结果并重读新范围', (tester) async {
    final store = _DelayedStore(ClockAccounts())..gate.complete();
    final backend = _Backend()..readGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: store,
    );
    addTearDown(controller.dispose);
    await _initialize(tester, controller);
    expect(backend.policies, isNotEmpty);
    await controller.setRoutePolicy(RoutePolicy.webvpn);
    backend.readGate!.complete();
    await tester.pump();
    expect(backend.policies, hasLength(2));
    expect(controller.homeSnapshots[FeatureId.schedule]!.details, isNotEmpty);
    expect(
      controller.homeSnapshots[FeatureId.schedule]!.resolvedRoute,
      ConnectionMode.webvpn,
    );
    expect(backend.opens, 1);
  });

  testWidgets('退出后的迟到密钥不能打开旧账号且仍清零', (tester) async {
    final store = _DelayedStore(ClockAccounts());
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: store,
    );
    addTearDown(controller.dispose);
    await _initialize(tester, controller);
    await controller.logout();
    store.gate.complete();
    await tester.pump();
    expect(store.key, everyElement(0));
    expect(backend.opens, 0);
    expect(controller.homeSnapshots[FeatureId.schedule]!.details, isEmpty);
  });
}

Future<void> _initialize(WidgetTester tester, AppController controller) async {
  final initialized = controller.initialize();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  await initialized;
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
  Future<void> clearOfflineAccount({required String accountId}) async {}
}

class _ManagedBackend extends _Backend implements CacheManagementBackend {
  @override
  Future<CacheClearOutcome> clearBusinessCache({
    required String accountId,
  }) async => const CacheClearOutcome(compacted: true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

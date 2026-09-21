import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'startup_test.dart' as support;

void main() {
  test('认证挂起时独立恢复缓存，认证失败保留原更新时间和内容', () async {
    final backend = _CachedBackend()..gate = Completer<AuthStatus>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final recovery = controller.recoverSession();
    await backend.cacheRead.future;
    await Future<void>.delayed(Duration.zero);
    final cached = controller.homeSnapshots[FeatureId.schedule]!;
    expect(cached.details.single.title, '已保存的合成课程');
    expect(cached.evidence?.origin, DataOrigin.persisted);
    expect(cached.updatedAt, backend.fetched);
    backend.gate!.completeError(
      const BackendException(UbaaErrorCode.networkError),
    );
    await recovery;
    expect(
      controller.homeSnapshots[FeatureId.schedule]!.updatedAt,
      backend.fetched,
    );
    expect(controller.phase, AppPhase.home);
  });

  test('在线读取失败不清空缓存且不能把保存时间更新为刚刚', () async {
    final backend = _CachedBackend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await backend.cacheRead.future;
    await Future<void>.delayed(Duration.zero);
    await controller.recoverSession();
    await controller.refreshHome(only: [FeatureId.schedule]);
    expect(
      controller.homeSnapshots[FeatureId.schedule]!.details.single.title,
      '已保存的合成课程',
    );
    expect(
      controller.homeSnapshots[FeatureId.schedule]!.updatedAt,
      backend.fetched,
    );
    expect(
      controller.snapshots[FeatureId.schedule]!.updatedAt,
      backend.fetched,
    );
  });

  test('迟到磁盘结果不能覆盖已经成功的在线课表', () async {
    final backend = _CachedBackend()
      ..diskGate = Completer<void>()
      ..online = const FeatureResult.success(
        details: [FeatureDetail(title: '本次在线课程')],
      );
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await backend.cacheRead.future;
    await controller.recoverSession();
    await controller.refreshHome(only: [FeatureId.schedule]);
    backend.diskGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.homeSnapshots[FeatureId.schedule]!.details.single.title,
      '本次在线课程',
    );
  });

  test('读取中的缓存迟到后遇到认证错误仍保留只读内容', () async {
    final backend = _CachedBackend()
      ..diskGate = Completer<void>()
      ..readGate = Completer<FeatureResult>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await backend.cacheRead.future;
    await controller.recoverSession();
    final reading = controller.refreshHome(only: [FeatureId.schedule]);
    backend.diskGate!.complete();
    await Future<void>.delayed(Duration.zero);
    backend.readGate!.complete(
      FeatureResult.failure(
        UbaaErrorMapper.fromCode(UbaaErrorCode.authenticationRequired),
      ),
    );
    await reading;
    expect(
      controller.snapshots[FeatureId.schedule]!.details.single.title,
      '已保存的合成课程',
    );
    expect(
      controller.snapshots[FeatureId.schedule]!.updatedAt,
      backend.fetched,
    );
  });

  test('退出后迟到磁盘内容不能重新显示', () async {
    final backend = _CachedBackend()..diskGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await backend.cacheRead.future;
    await controller.logout();
    backend.diskGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.homeSnapshots[FeatureId.schedule]!.details, isEmpty);
    expect(controller.phase, AppPhase.login);
  });

  test('原位改登另一账号时先关闭旧缓存并清除旧账号内容', () async {
    final backend = _CachedBackend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await backend.cacheRead.future;
    await Future<void>.delayed(Duration.zero);
    backend.username = 'second-fixture';
    backend.diskGate = Completer<void>();
    controller.setUsername('second-fixture');
    controller.setPassword('synthetic-password');
    final login = controller.submitLogin(preserveHome: true);
    await backend.secondOpen.future;
    try {
      expect(controller.homeSnapshots[FeatureId.schedule]!.details, isEmpty);
      expect(backend.deactivated, 1);
    } finally {
      backend.diskGate!.complete();
      await login;
    }
  });

  test('学校注销挂起也立即隐藏本机个人投影', () async {
    final backend = _CachedBackend()..logoutGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await backend.cacheRead.future;
    await Future<void>.delayed(Duration.zero);
    final closing = controller.logout();
    try {
      expect(controller.phase, AppPhase.login);
      expect(controller.homeSnapshots[FeatureId.schedule]!.details, isEmpty);
      controller.setUsername('fixture-user');
      controller.setPassword('synthetic-password');
      await controller.submitLogin();
      expect(backend.loginCalls, 0);
    } finally {
      backend.logoutGate!.complete();
      await closing;
    }
  });

  test('退出先关闭持久缓存，使正在后台返回的数据无权回写', () async {
    final backend = _CachedBackend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await backend.cacheRead.future;
    await controller.logout();
    expect(backend.deactivated, 1);
    expect(controller.homeSnapshots[FeatureId.schedule]!.details, isEmpty);
  });
}

class _CachedBackend extends support.FakeRecoveryBackend
    implements OfflineCacheBackend {
  final fetched = DateTime.now().subtract(const Duration(minutes: 20));
  final cacheRead = Completer<void>();
  final secondOpen = Completer<void>();
  LocalAccount? account;
  int deactivated = 0;
  Completer<void>? diskGate;
  Completer<void>? logoutGate;
  @override
  Future<void> logout() async {
    await logoutGate?.future;
  }

  Completer<FeatureResult>? readGate;
  FeatureResult? online;
  @override
  Future<void> openOfflineAccount(LocalAccount value, List<int> key) async {
    if (account != null && !secondOpen.isCompleted) secondOpen.complete();
    account = value;
  }

  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) async {
    final result = [
      CachedFeatureProjection(
        feature: FeatureId.schedule,
        accountId: account!.id,
        route: ConnectionMode.direct,
        fetchedAt: fetched,
        complete: true,
        details: const [FeatureDetail(title: '已保存的合成课程')],
      ),
    ];
    if (!cacheRead.isCompleted) cacheRead.complete();
    await diskGate?.future;
    return OfflineHomeRead(result);
  }

  @override
  Future<void> deactivateOfflineAccount() async {
    deactivated++;
  }

  @override
  Future<void> clearOfflineAccount() async {}
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      await readGate?.future ??
      online ??
      const FeatureResult.failure(
        UiError(
          code: UbaaErrorCode.networkError,
          title: '网络不可用',
          message: '合成读取失败',
          retryable: true,
        ),
      );
}

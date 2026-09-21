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
    final chosen = controller.homeSnapshots[FeatureId.bykc]!;
    expect(chosen.details.single.title, '已保存博雅');
    expect(
      controller.homeSnapshots[FeatureId.cgyy]!.details.single.title,
      '已保存研讨室',
    );
    expect(
      controller.homeSnapshots[FeatureId.cgyy]!.readContext?.query?.view,
      FeatureQueryView.cgyyOrders,
    );
    expect(controller.snapshots[FeatureId.cgyy]!.details, isEmpty);
    expect(chosen.readContext?.query?.view, FeatureQueryView.bykcChosenCourses);
    expect(controller.snapshots[FeatureId.bykc]!.details, isEmpty);
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
  test('仍在更新的混合来源内容不能被迟到磁盘投影覆盖', () async {
    final backend = _MixedBackend()..diskGate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await backend.cacheRead.future;
    await controller.recoverSession();
    for (var i = 0; i < 100 && backend.task.calls < 2; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(backend.task.calls, 2);
    backend.diskGate!.complete();
    await Future<void>.delayed(Duration.zero);
    final snapshot = controller.homeSnapshots[FeatureId.schedule]!;
    expect(snapshot.status, FeatureLoadStatus.loading);
    expect(snapshot.evidence?.origin, DataOrigin.mixed);
    expect(snapshot.details.single.title, '新旧混合课程');
    backend.task.finish.complete(
      FeatureReadBatch(backend.mixedResult(), finished: true),
    );
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
        feature: FeatureId.cgyy,
        query: const FeatureQuery(view: FeatureQueryView.cgyyOrders),
        accountId: account!.id,
        route: ConnectionMode.direct,
        fetchedAt: fetched,
        complete: true,
        details: const [FeatureDetail(title: '已保存研讨室')],
      ),
      CachedFeatureProjection(
        feature: FeatureId.bykc,
        query: const FeatureQuery(view: FeatureQueryView.bykcChosenCourses),
        accountId: account!.id,
        route: ConnectionMode.direct,
        fetchedAt: fetched,
        complete: true,
        details: const [FeatureDetail(title: '已保存博雅')],
      ),
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

class _MixedBackend extends _CachedBackend implements ProgressiveReadBackend {
  late final task = _MixedTask(mixedResult);
  FeatureResult mixedResult() => FeatureResult.success(
    details: const [FeatureDetail(title: '新旧混合课程')],
    evidence: DataEvidence(
      accountId: account!.id,
      origin: DataOrigin.mixed,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(100000),
      complete: false,
      savedForOffline: false,
    ),
  );
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => feature == FeatureId.schedule ? task : null;
}

class _MixedTask implements FeatureReadTask {
  _MixedTask(this.result);
  final FeatureResult Function() result;
  final finish = Completer<FeatureReadBatch>();
  int calls = 0;
  @override
  Future<FeatureReadBatch> next() async => ++calls == 1
      ? FeatureReadBatch(result(), finished: false)
      : finish.future;
  @override
  void cancel() {}
}

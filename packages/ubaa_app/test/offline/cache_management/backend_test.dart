import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

const account = LocalAccount(id: 'synthetic-a', username: 'synthetic');
final conflict = throwsA(
  isA<BackendException>().having(
    (e) => e.code,
    '代际失效',
    UbaaErrorCode.operationConflict,
  ),
);
void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() {
    api.failOpen = false;
    api.ready = true;
    api.rebuilds = 0;
    api.rebuildGate = null;
  });
  Future<BridgeBackend> open() async {
    api.cache = _Cache();
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await backend.openOfflineAccount(account, List.filled(32, 1));
    return backend;
  }

  test('普通打开失败不自动重建，显式重建仍核对目标账号', () async {
    api.cache = _Cache();
    api.failOpen = true;
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await expectLater(
      backend.openOfflineAccount(account, List.filled(32, 1)),
      throwsA(isA<BackendException>()),
    );
    expect(api.rebuilds, 0);
    await expectLater(
      backend.clearOrRebuildBusinessCache(
        account: const LocalAccount(id: 'other', username: 'other'),
        key: List.filled(32, 1),
      ),
      conflict,
    );
    final value = await backend.clearOrRebuildBusinessCache(
      account: account,
      key: List.filled(32, 1),
    );
    expect(value.cacheReady, isTrue);
    expect(api.rebuilds, 1);
    expect((await backend.cacheUsage(accountId: account.id)).entryCount, 0);
  });
  test('重建后初始化失败不继续使用旧句柄', () async {
    final backend = await open();
    api.ready = false;
    final result = await backend.clearOrRebuildBusinessCache(
      account: account,
      key: List.filled(32, 1),
    );
    expect(result.cacheReady, isFalse);
    expect(result.maintenanceError, CacheMaintenanceFailure.capacity);
    await expectLater(backend.cacheUsage(accountId: account.id), conflict);
  });
  test('重建拒绝旧读取交付并把排队退出应用到继任句柄', () async {
    final backend = await open();
    final old = api.cache;
    old.profileGate = Completer<void>();
    final pending = backend.readCachedProfile(RoutePolicy.direct);
    final checked = expectLater(pending, conflict);
    await old.profileStarted.future;
    api.rebuildGate = Completer<void>();
    final clearing = backend.clearOrRebuildBusinessCache(
      account: account,
      key: List.filled(32, 1),
    );
    final logout = backend.deactivateOfflineAccount();
    api.rebuildGate!.complete();
    await clearing;
    await logout;
    old.profileGate!.complete();
    await checked;
    expect(api.recovered!.deactivateCalls, 1);
  });
  test('数值用量与清理均核对账号，维护失败仍交付新句柄', () async {
    final backend = await open();
    final old = api.cache;
    final usage = await backend.cacheUsage(accountId: account.id);
    expect(usage.entryCount, 3);
    await expectLater(backend.clearBusinessCache(accountId: 'other'), conflict);
    expect(old.clearCalls, 0);
    old.maintenanceError = BridgeCacheFailure.unavailable;
    final result = await backend.clearBusinessCache(accountId: account.id);
    expect(result.maintenanceError, CacheMaintenanceFailure.unavailable);
    expect(result.compacted, isFalse);
    expect((await backend.cacheUsage(accountId: account.id)).entryCount, 0);
    expect(old.clearCalls, 1);
    expect(old.usageCalls, 1);
  });
  test('事务失败保留旧句柄且串行通道仍可继续', () async {
    final backend = await open();
    api.cache.failClear = true;
    await expectLater(
      backend.clearBusinessCache(accountId: account.id),
      throwsA(isA<BackendException>()),
    );
    expect((await backend.cacheUsage(accountId: account.id)).entryCount, 3);
    api.cache.failClear = false;
    await backend.clearBusinessCache(accountId: account.id);
    expect((await backend.cacheUsage(accountId: account.id)).entryCount, 0);
  });
  test('清理排队前的读取失效，排队后的读取等待新句柄', () async {
    final backend = await open();
    final old = api.cache;
    old.clearGate = Completer<void>();
    final stale = backend.readCachedProfile(RoutePolicy.direct);
    final staleCheck = expectLater(stale, conflict);
    final clearing = backend.clearBusinessCache(accountId: account.id);
    final fresh = backend.readCachedProfile(RoutePolicy.direct);
    await Future<void>.delayed(Duration.zero);
    expect(old.profileCalls, 0);
    old.clearGate!.complete();
    await clearing;
    await staleCheck;
    await fresh;
    expect(old.successor.profileCalls, 1);
  });
  test('清理期间迟到的资料不交付给调用者，退出作用于继任句柄', () async {
    final backend = await open();
    final old = api.cache;
    old.profileGate = Completer<void>();
    final pending = backend.readCachedProfile(RoutePolicy.direct);
    final check = expectLater(pending, conflict);
    await old.profileStarted.future;
    final clearing = backend.clearBusinessCache(accountId: account.id);
    final logout = backend.deactivateOfflineAccount();
    await clearing;
    await logout;
    old.profileGate!.complete();
    await check;
    expect(old.successor.deactivateCalls, 1);
    expect(old.deactivateCalls, 0);
  });
  test('待切换账号已排队时，旧确认不能清理新账号或旧账号', () async {
    final backend = await open();
    final old = api.cache;
    api.cache = _Cache();
    final opening = backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic-b', username: 'another'),
      List.filled(32, 2),
    );
    await expectLater(
      backend.clearBusinessCache(accountId: account.id),
      conflict,
    );
    await opening;
    expect(old.clearCalls, 0);
    expect(api.cache.clearCalls, 0);
  });
}

class _Api implements RustLibApi {
  late _Cache cache;
  bool failOpen = false, ready = true;
  int rebuilds = 0;
  Completer<void>? rebuildGate;
  _Cache? recovered;
  @override
  Future<BridgeCacheRecovery> crateApiOfflineBridgeOfflineCacheClearOrRebuild({
    required String configDir,
    required String accountId,
    required String expectedIdentity,
    required List<int> key,
  }) async {
    rebuilds++;
    expect(expectedIdentity, 'synthetic');
    await rebuildGate?.future;
    recovered = ready ? _Cache(count: 0) : null;
    return BridgeCacheRecovery(
      cache: recovered,
      report: BridgeCacheClearReport(
        compacted: true,
        maintenanceError: ready ? null : BridgeCacheFailure.capacity,
      ),
    );
  }

  @override
  Future<BridgeOfflineCache> crateApiOfflineBridgeOfflineCacheOpen({
    required String configDir,
    required String accountId,
    required String expectedIdentity,
    required List<int> key,
  }) async {
    if (failOpen)
      throw const BridgeError(
        code: BridgeErrorCode.internalError,
        kind: BridgeErrorKind.internal,
        retryable: false,
        message: '合成损坏',
      );
    return cache;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  @override
  int contractVersion() => 26;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements BridgeOfflineCache {
  _Cache({this.count = 3});
  final int count;
  late final successor = _Cache(count: 0);
  int clearCalls = 0, usageCalls = 0, profileCalls = 0, deactivateCalls = 0;
  bool failClear = false;
  BridgeCacheFailure? maintenanceError;
  Completer<void>? clearGate, profileGate;
  final profileStarted = Completer<void>();
  @override
  Future<void> activate() async {}
  @override
  Future<void> deactivate() async {
    deactivateCalls++;
  }

  @override
  Future<BridgeCacheUsage> usage() async {
    usageCalls++;
    return BridgeCacheUsage(
      entryCount: BigInt.from(count),
      contentBytes: BigInt.from(count * 10),
      databaseBytes: BigInt.from(4096),
      reusableBytes: BigInt.zero,
      softLimitBytes: BigInt.from(50 * 1024 * 1024),
      hardLimitBytes: BigInt.from(100 * 1024 * 1024),
    );
  }

  @override
  Future<BridgeCacheReset> clearAndReopen() async {
    clearCalls++;
    await clearGate?.future;
    if (failClear)
      throw const BridgeError(
        code: BridgeErrorCode.internalError,
        message: '合成事务失败',
        kind: BridgeErrorKind.internal,
        retryable: false,
      );
    return BridgeCacheReset(
      cache: successor,
      report: BridgeCacheClearReport(
        usage: await successor.usage(),
        compacted: maintenanceError == null,
        maintenanceError: maintenanceError,
      ),
    );
  }

  @override
  Future<BridgeCachedProfile?> readProfile({
    required BridgeConnectionMode route,
  }) async {
    profileCalls++;
    if (!profileStarted.isCompleted) profileStarted.complete();
    await profileGate?.future;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

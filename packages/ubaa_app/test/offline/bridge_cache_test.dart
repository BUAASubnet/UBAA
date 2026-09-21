import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  test('实际缓存路线与原时间不被配置策略改写，且不会校验网络会话', () async {
    final cache = _Cache();
    api.cache = cache;
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    final records = await backend.readCachedHome(RoutePolicy.webvpn);
    expect(cache.reads, [BridgeConnectionMode.webVpn]);
    expect(records.single.route, ConnectionMode.webvpn);
    expect(records.single.fetchedAt.millisecondsSinceEpoch, 1700000000000);
    expect(records.single.toSnapshot().details.single.actions, isEmpty);
    expect(records.single.scopeDate, '2026-09-21');
  });
  test('打开缓存被挂起时随后退出，启用不能越过停用重新开放账号', () async {
    final cache = _Cache()..activateGate = Completer<void>();
    api.cache = cache;
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    final opening = backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    final closing = backend.deactivateOfflineAccount();
    await Future<void>.delayed(Duration.zero);
    cache.activateGate!.complete();
    await opening;
    await closing;
    expect(cache.events, ['activate', 'deactivate']);
  });
}

class _Api implements RustLibApi {
  late _Cache cache;
  @override
  Future<BridgeOfflineCache> crateApiOfflineBridgeOfflineCacheOpen({
    required String configDir,
    required String accountId,
    required String expectedIdentity,
    required List<int> key,
  }) async => cache;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  @override
  int contractVersion() => 10;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements BridgeOfflineCache {
  final reads = <BridgeConnectionMode>[];
  final events = <String>[];
  Completer<void>? activateGate;
  @override
  Future<void> activate() async {
    await activateGate?.future;
    events.add('activate');
  }

  @override
  Future<void> deactivate() async {
    events.add('deactivate');
  }

  @override
  Future<BridgeCachedToday?> readToday({
    required BridgeConnectionMode route,
  }) async {
    reads.add(route);
    return BridgeCachedToday(
      data: const [BridgeTodayClass(bizName: '合成课表', time: '08:00')],
      sourceRoute: route,
      date: '2026-09-21',
      fetchedAt: 1700000000,
      complete: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

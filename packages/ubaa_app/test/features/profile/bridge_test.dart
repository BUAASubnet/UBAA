import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('密钥或缓存不可用时仍可在线读资料且不声明已保存', () async {
    final client = _Client();
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    final value = await backend.refreshProfile(
      account: const LocalAccount(id: 'synthetic', username: 'synthetic'),
    );
    expect(value.profile.username, 'synthetic');
    expect(value.evidence.savedForOffline, isFalse);
    expect(client.plainCalls, 1);
    expect(client.cachedCalls, 0);
  });

  setUpAll(() => RustLib.initMock(api: _Api()));
  test('旧缓存仅有学号时仍保留姓名与展示字段', () async {
    final previous = _Cache.data;
    addTearDown(() => _Cache.data = previous);
    _Cache.data = const BridgeUserProfile(
      name: '合成姓名',
      schoolId: 'T***1',
      phone: '000****0000',
      email: 's***t@example.invalid',
    );
    final backend = await open(_Client());
    final display = (await backend.readCachedProfile(
      RoutePolicy.auto,
    )).profile!.toDisplay();
    expect(display.username, 'T***1');
    expect(display.displayName, '合成姓名');
    expect(display.phone, '000****0000');
    expect(display.email, 's***t@example.invalid');
  });

  test('资料本地通道跨路线共用最新记录且不借遮罩值建立身份', () async {
    final backend = await open(_Client());
    final result = await backend.readCachedProfile(RoutePolicy.auto);
    final value = result.profile!;
    expect(value.route, ConnectionMode.webvpn);
    expect(value.profile.username, 's***c');
    expect(value.fetchedAt.millisecondsSinceEpoch, 200000);
    final display = value.toDisplay();
    expect(display.profileEvidence!.origin, DataOrigin.persisted);
    expect(display.phone, isNull);
    expect(display.email, isNull);
    final direct = await backend.readCachedProfile(RoutePolicy.direct);
    expect(direct.profile!.fetchedAt.millisecondsSinceEpoch, 200000);
  });
  test('在线缓存刷新保留原资料且原userInfo不隐式改为恢复入口', () async {
    final client = _Client();
    final backend = await open(client);
    final value = await backend.refreshProfile(
      account: const LocalAccount(id: 'synthetic', username: 'synthetic'),
    );
    expect(value.profile.username, 'synthetic');
    expect(value.profile.phone, '合成手机');
    expect(value.evidence.origin, DataOrigin.online);
    expect(value.evidence.savedForOffline, isTrue);
    expect(value.evidence.fetchedAt.millisecondsSinceEpoch, 300000);
    await backend.userInfo();
    expect(client.cachedCalls, 1);
    expect(client.plainCalls, 1);
  });
}

Future<BridgeBackend> open(_Client client) async {
  final backend = BridgeBackend(client, configDirectory: '/synthetic');
  await backend.openOfflineAccount(
    const LocalAccount(id: 'synthetic', username: 'synthetic'),
    List.filled(32, 1),
  );
  return backend;
}

class _Api implements RustLibApi {
  @override
  Future<BridgeOfflineCache> crateApiOfflineBridgeOfflineCacheOpen({
    required String configDir,
    required String accountId,
    required String expectedIdentity,
    required List<int> key,
  }) async => _Cache();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements BridgeOfflineCache {
  static BridgeUserProfile data = const BridgeUserProfile(
    username: 's***c',
    name: '合***名',
    schoolId: 'T***1',
  );
  @override
  Future<void> close() async {}

  @override
  void dispose() {}

  @override
  Future<void> activate() async {}
  @override
  Future<BridgeCachedProfile?> readProfile({
    required BridgeConnectionMode route,
  }) async => BridgeCachedProfile(
    data: data,
    sourceRoute: BridgeConnectionMode.webVpn,
    fetchedAt: 200,
    complete: true,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const profile = BridgeUserProfile(
  username: 'synthetic',
  name: '合成姓名',
  schoolId: 'TEST1',
  phone: '合成手机',
  email: 'synthetic@example.invalid',
);
const route = BridgeRouteDecision(
  policy: BridgeRoutePolicy.direct,
  resolvedRoute: BridgeConnectionMode.direct,
  network: BridgeNetworkState.unknown,
  initialRoute: BridgeConnectionMode.direct,
  usedFallback: false,
);

class _Client implements BridgeClient {
  int cachedCalls = 0, plainCalls = 0;
  @override
  int contractVersion() => 54;
  @override
  Future<BridgeProfileRefresh> userInfoCached({
    required BridgeOfflineCache cache,
  }) async {
    cachedCalls++;
    return const BridgeProfileRefresh(
      data: profile,
      route: route,
      fetchedAt: 300,
      savedForOffline: true,
    );
  }

  @override
  Future<BridgeRoutedUserProfile> userInfo() async {
    plainCalls++;
    return const BridgeRoutedUserProfile(data: profile, route: route);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

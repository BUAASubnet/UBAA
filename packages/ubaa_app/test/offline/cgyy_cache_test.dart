import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('研讨室异范围响应无旧缓存时只报告未完整而不展示别日别单别页', () async {
    _Cache.hasScopedCache = false;
    final backend = BridgeBackend(
      _Client()..wrongOrders = true,
      configDirectory: '/synthetic',
    );
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    for (final query in [
      FeatureQuery(
        view: FeatureQueryView.cgyyDayInfo,
        siteId: 4,
        date: DateTime(2026, 9, 22),
      ),
      const FeatureQuery(view: FeatureQueryView.cgyyOrderDetail, orderId: 9),
      const FeatureQuery(view: FeatureQueryView.cgyyOrders, page: 1, size: 20),
    ]) {
      final result = await backend.loadFeatureQuery(FeatureId.cgyy, query);
      expect(result.evidence!.complete, isFalse);
      expect(result.details, isEmpty, reason: query.view.name);
      expect(result.pagination, isNull);
    }
  });
  test('站点导航保留查询日期，详情和首页订单均只读', () async {
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    final date = DateTime(2026, 9, 22);
    final sites = await backend.readCachedQuery(
      FeatureId.cgyy,
      FeatureQuery(date: date),
      RoutePolicy.direct,
    );
    expect(sites.projection!.details.single.readNavigation!.query.date, date);
    final detail = await backend.readCachedQuery(
      FeatureId.cgyy,
      const FeatureQuery(view: FeatureQueryView.cgyyOrderDetail, orderId: 9),
      RoutePolicy.direct,
    );
    expect(detail.projection!.details.single.actions, isEmpty);
    final home = await backend.readCachedHome(RoutePolicy.direct);
    expect(home.single.readContext.query!.view, FeatureQueryView.cgyyOrders);
    expect(home.single.details.single.actions, isEmpty);
  });

  setUp(() {
    _Cache.firstFallback = false;
    _Cache.hasScopedCache = true;
  });
  test('首次保存的静态回退仍标为本次部分结果，不冒称保留旧动态数据', () async {
    _Cache.firstFallback = true;
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    final result = await backend.loadFeatureQuery(
      FeatureId.cgyy,
      const FeatureQuery(view: FeatureQueryView.cgyyPurposeTypes),
    );
    expect(result.evidence!.origin, DataOrigin.online);
    expect(result.evidence!.complete, isFalse);
    expect(result.evidence!.savedForOffline, isTrue);
    expect(
      (result.details.single.presentation as CgyyPurposePresentation)
          .isStaticFallback,
      isTrue,
    );
  });

  test('用途回退与错日期响应保留原范围缓存且不恢复预约资格', () async {
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    const purposes = FeatureQuery(view: FeatureQueryView.cgyyPurposeTypes);
    final value = await backend.loadFeatureQuery(FeatureId.cgyy, purposes);
    expect(value.details.single.title, '旧学术研讨类');
    expect(value.evidence!.origin, DataOrigin.persisted);
    expect(value.evidence!.complete, isFalse);
    final dayQuery = FeatureQuery(
      view: FeatureQueryView.cgyyDayInfo,
      siteId: 4,
      date: DateTime(2026, 9, 22),
    );
    final day = await backend.loadFeatureQuery(FeatureId.cgyy, dayQuery);
    expect(
      (day.details.first.presentation as CgyyDayPresentation).reservationDate,
      '2026-09-22',
    );
    expect(day.details.expand((v) => v.actions), isEmpty);
    expect(day.evidence!.complete, isFalse);
    expect(day.evidence!.origin, DataOrigin.persisted);
    final cached = await backend.readCachedQuery(
      FeatureId.cgyy,
      dayQuery,
      RoutePolicy.direct,
    );
    expect(cached.projection!.details.expand((v) => v.actions), isEmpty);
  });

  setUpAll(() => RustLib.initMock(api: _Api()));
  test('研讨室缓存页保留页信息且不恢复取消资格，预约回读绕过缓存认证', () async {
    final client = _Client();
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    const query = FeatureQuery(
      view: FeatureQueryView.cgyyOrders,
      page: 1,
      size: 20,
    );
    final read = await backend.readCachedQuery(
      FeatureId.cgyy,
      query,
      RoutePolicy.direct,
    );
    expect(read.projection, isNotNull);
    final snapshot = read.projection!.toSnapshot();
    expect(snapshot.pagination?.page, 2);
    expect(snapshot.pagination?.total, 21);
    expect(snapshot.details.single.actions, isEmpty);
    expect(_Cache.page, 1);
    final fresh = await backend.loadFeatureQuery(FeatureId.cgyy, query);
    expect(
      fresh.details.single.actions
          .whereType<CgyyCancelAction>()
          .single
          .eligibility,
      ActionEligibility.allowed,
    );
    expect(fresh.evidence!.origin, DataOrigin.online);
    await (backend as CgyyReservationReadbackBackend).readCgyyAfterWrite(query);
    expect(client.cachedCalls, 1);
    expect(client.plainCalls, 1);
  });
}

const route = BridgeRouteDecision(
  policy: BridgeRoutePolicy.direct,
  resolvedRoute: BridgeConnectionMode.direct,
  network: BridgeNetworkState.unknown,
  initialRoute: BridgeConnectionMode.direct,
  usedFallback: false,
);
const order = BridgeCgyyOrder(
  id: 9,
  theme: '合成预约',
  cancelEligibility: BridgeActionEligibility.allowed,
  cancelTarget: BridgeCgyyCancelOrderTarget(orderId: 9),
);
const orders = BridgeCgyyOrdersPage(
  content: [order],
  totalElements: 21,
  totalPages: 2,
  size: 20,
  number: 1,
);

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
  static int? page;
  static bool hasScopedCache = true;
  @override
  Future<BridgeCachedCgyySitesRecord?> readCgyySites({
    required BridgeConnectionMode route,
  }) async => BridgeCachedCgyySitesRecord(
    data: const [
      BridgeCgyyVenueSite(
        id: 4,
        siteName: '合成楼',
        venueName: '合成场馆',
        campusName: '合成校区',
      ),
    ],
    sourceRoute: route,
    fetchedAt: 100,
    complete: true,
  );
  @override
  Future<BridgeCachedCgyyDetailRecord?> readCgyyDetail({
    required BridgeConnectionMode route,
    required int orderId,
  }) async => !hasScopedCache
      ? null
      : BridgeCachedCgyyDetailRecord(
          data: BridgeCachedCgyyOrder(id: orderId, theme: '合成预约'),
          sourceRoute: route,
          fetchedAt: 100,
          complete: true,
        );
  @override
  Future<BridgeCachedToday?> readToday({
    required BridgeConnectionMode route,
  }) async => null;
  @override
  Future<BridgeCachedJudge?> readJudge({
    required BridgeConnectionMode route,
    required bool includeExpired,
  }) async => null;
  @override
  Future<BridgeCachedHomeSignin?> readHomeSignin({
    required BridgeConnectionMode route,
  }) async => null;
  @override
  Future<BridgeCachedHomeSpoc?> readHomeSpoc({
    required BridgeConnectionMode route,
  }) async => null;
  @override
  Future<BridgeCachedHomeYgdk?> readHomeYgdk({
    required BridgeConnectionMode route,
  }) async => null;
  @override
  Future<BridgeCachedBykcChosenRecord?> readBykcChosen({
    required BridgeConnectionMode route,
  }) async => null;

  static bool firstFallback = false;
  @override
  Future<BridgeCachedCgyyPurposesRecord?> readCgyyPurposes({
    required BridgeConnectionMode route,
  }) async => BridgeCachedCgyyPurposesRecord(
    data: firstFallback
        ? fallbackPurposes
        : const BridgeCgyyPurposeTypes(
            items: [BridgeCgyyPurposeType(key: 3, name: '旧学术研讨类')],
            source: BridgeCgyyPurposeSource.upstream,
          ),
    sourceRoute: route,
    fetchedAt: firstFallback ? 200 : 100,
    complete: !firstFallback,
  );
  @override
  Future<BridgeCachedCgyyDayRecord?> readCgyyDay({
    required BridgeConnectionMode route,
    required int siteId,
    required String date,
  }) async => !hasScopedCache
      ? null
      : BridgeCachedCgyyDayRecord(
          data: BridgeCachedCgyyDayInfo(
            venueSiteId: siteId,
            reservationDate: date,
            availableDates: [date],
            timeSlots: const [
              BridgeCgyyTimeSlot(
                id: 1,
                beginTime: '08:00',
                endTime: '09:00',
                label: '08:00–09:00',
              ),
            ],
            spaces: const [
              BridgeCachedCgyySpaceAvailability(
                spaceId: 6,
                spaceName: '合成研讨室',
                venueSiteId: 4,
                slots: [
                  BridgeCachedCgyySlotStatus(timeId: 1, reservationStatus: 1),
                ],
              ),
            ],
          ),
          sourceRoute: route,
          fetchedAt: 100,
          complete: true,
        );

  @override
  Future<void> activate() async {}
  @override
  Future<BridgeCachedCgyyOrdersRecord?> readCgyyOrders({
    required BridgeConnectionMode route,
    required int page,
    required int size,
  }) async {
    _Cache.page = page;
    if (!hasScopedCache) return null;
    return BridgeCachedCgyyOrdersRecord(
      data: BridgeCachedCgyyOrdersPage(
        content: [BridgeCachedCgyyOrder(id: 9, theme: '合成预约')],
        totalElements: 21,
        totalPages: 2,
        size: 20,
        number: page,
      ),
      sourceRoute: route,
      fetchedAt: 100,
      complete: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  int cachedCalls = 0, plainCalls = 0;
  bool wrongOrders = false;
  @override
  Future<BridgeCgyyDetailRefresh> cgyyDetailCached({
    required BridgeOfflineCache cache,
    required int orderId,
  }) async => const BridgeCgyyDetailRefresh(
    data: BridgeCgyyOrder(
      id: 88,
      theme: '别的订单',
      cancelEligibility: BridgeActionEligibility.allowed,
      cancelTarget: BridgeCgyyCancelOrderTarget(orderId: 88),
    ),
    route: route,
    state: BridgeCgyyRefreshState(
      fetchedAt: 200,
      complete: false,
      savedForOffline: false,
      preservedPrevious: false,
      saveError: BridgeCacheFailure.invalidInput,
    ),
  );

  @override
  Future<BridgeCgyyPurposesRefresh> cgyyPurposesCached({
    required BridgeOfflineCache cache,
  }) async => BridgeCgyyPurposesRefresh(
    data: fallbackPurposes,
    route: route,
    state: BridgeCgyyRefreshState(
      fetchedAt: 200,
      complete: false,
      savedForOffline: _Cache.firstFallback,
      preservedPrevious: !_Cache.firstFallback,
    ),
  );
  @override
  Future<BridgeCgyyDayRefresh> cgyyDayCached({
    required BridgeOfflineCache cache,
    required int siteId,
    required String date,
  }) async => BridgeCgyyDayRefresh(
    data: BridgeCgyyDayInfo(
      venueSiteId: siteId,
      reservationDate: '2026-09-23',
      availableDates: const ['2026-09-23'],
      timeSlots: const [],
      spaces: const [],
    ),
    route: route,
    state: const BridgeCgyyRefreshState(
      fetchedAt: 200,
      complete: false,
      savedForOffline: false,
      preservedPrevious: false,
      saveError: BridgeCacheFailure.invalidInput,
    ),
  );

  @override
  int contractVersion() => 33;
  @override
  Future<BridgeCgyyOrdersRefresh> cgyyOrdersCached({
    required BridgeOfflineCache cache,
    required int page,
    required int size,
  }) async {
    cachedCalls++;
    if (wrongOrders)
      return const BridgeCgyyOrdersRefresh(
        data: BridgeCgyyOrdersPage(
          content: [order],
          totalElements: 21,
          totalPages: 2,
          size: 20,
          number: 9,
        ),
        route: route,
        state: BridgeCgyyRefreshState(
          fetchedAt: 200,
          complete: false,
          savedForOffline: false,
          preservedPrevious: false,
          saveError: BridgeCacheFailure.invalidInput,
        ),
      );
    return const BridgeCgyyOrdersRefresh(
      data: orders,
      route: route,
      state: BridgeCgyyRefreshState(
        fetchedAt: 200,
        complete: true,
        savedForOffline: true,
        preservedPrevious: false,
      ),
    );
  }

  @override
  Future<BridgeRoutedCgyyOrders> cgyyOrders({
    required int page,
    required int size,
  }) async {
    plainCalls++;
    return const BridgeRoutedCgyyOrders(data: orders, route: route);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const fallbackPurposes = BridgeCgyyPurposeTypes(
  items: [BridgeCgyyPurposeType(key: 1, name: '静态回退类')],
  source: BridgeCgyyPurposeSource.staticFallback,
);

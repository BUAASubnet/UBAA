import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _Api()));
  setUp(() => _Cache.hasBookings = true);
  test('明确错页且没有旧缓存时不能把别页放进当前查询', () async {
    _Cache.hasBookings = false;
    final client = _Client()
      ..partial = true
      ..wrongPage = true;
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    final value = await backend.loadFeatureQuery(
      FeatureId.libbook,
      const FeatureQuery(
        view: FeatureQueryView.libbookBookings,
        page: 2,
        size: 20,
      ),
    );
    expect(value.evidence!.complete, isFalse);
    expect(value.pagination, isNull);
    expect(value.details, isEmpty);
  });
  test('缺时段上下文在缓存网络读取前拒绝', () async {
    final client = _Client();
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    await expectLater(
      backend.loadFeatureQuery(
        FeatureId.libbook,
        FeatureQuery(
          view: FeatureQueryView.libbookSeats,
          areaId: 'a1',
          date: DateTime(2026, 9, 22),
          startTime: '08:00',
          endTime: '09:00',
        ),
      ),
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          '本地输入拒绝',
          UbaaErrorCode.invalidInput,
        ),
      ),
    );
    expect(client.seatCalls, 0);
  });
  test('楼馆分区详情沿精确日期与父查询恢复', () async {
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    final date = DateTime(2026, 9, 22);
    final libraries = await backend.readCachedQuery(
      FeatureId.libbook,
      FeatureQuery(date: date),
      RoutePolicy.direct,
    );
    expect(
      (libraries.projection!.details.single.presentation
              as LibbookLibraryPresentation)
          .queryDate,
      '2026-09-22',
    );
    final areas = await backend.readCachedQuery(
      FeatureId.libbook,
      FeatureQuery(
        view: FeatureQueryView.libbookAreas,
        premisesId: 'p1',
        storeyId: 'f1',
        date: date,
      ),
      RoutePolicy.direct,
    );
    expect(areas.projection!.details.single.readNavigation!.query.date, date);
    expect(_Cache.areaParameters, ['p1', 'f1', '2026-09-22']);
    final detail = await backend.readCachedQuery(
      FeatureId.libbook,
      const FeatureQuery(
        view: FeatureQueryView.libbookAreaDetail,
        areaId: 'a1',
      ),
      RoutePolicy.direct,
    );
    expect(detail.projection!.details.single.actions, isEmpty);
  });
  test('不完整预约刷新保留原页和时间且不产生取消动作', () async {
    final client = _Client()..partial = true;
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    final value = await backend.loadFeatureQuery(
      FeatureId.libbook,
      const FeatureQuery(
        view: FeatureQueryView.libbookBookings,
        page: 2,
        size: 20,
      ),
    );
    expect(value.details.single.title, '合成预约');
    expect(value.details.single.actions, isEmpty);
    expect(value.evidence!.origin, DataOrigin.persisted);
    expect(value.evidence!.complete, isFalse);
    expect(value.evidence!.fetchedAt.millisecondsSinceEpoch, 100000);
    expect(value.pagination!.page, 2);
  });
  test('离线座位保留日期时段但没有预约资格与动作', () async {
    final backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    final query = FeatureQuery(
      view: FeatureQueryView.libbookSeats,
      areaId: 'a1',
      date: DateTime(2026, 9, 22),
      segment: 'segment',
      startTime: '08:00',
      endTime: '09:00',
    );
    final value = await backend.readCachedQuery(
      FeatureId.libbook,
      query,
      RoutePolicy.direct,
    );
    expect(value.projection, isNotNull);
    final detail = value.projection!.details.single;
    expect(detail.actions, isEmpty);
    expect(detail.fields.any((field) => field.label == '可预约'), isFalse);
    final view = detail.presentation as LibbookSeatPresentation;
    expect(view.queryDate, '2026-09-22');
    expect(view.segment, 'segment');
    expect(_Cache.parameters, ['a1', '2026-09-22', '08:00', '09:00']);
  });
  test('预约记录保留分页且既定写后回读绕过缓存恢复', () async {
    final client = _Client();
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    const query = FeatureQuery(
      view: FeatureQueryView.libbookBookings,
      page: 2,
      size: 20,
    );
    final value = await backend.readCachedQuery(
      FeatureId.libbook,
      query,
      RoutePolicy.direct,
    );
    expect(value.projection!.pagination!.page, 2);
    expect(value.projection!.details.single.actions, isEmpty);
    await backend.loadFeatureQuery(FeatureId.libbook, query);
    await (backend as LibbookReadbackBackend).readLibbookAfterWrite(query);
    expect(client.cachedCalls, 1);
    expect(client.plainCalls, 1);
  });
}

const decision = BridgeRouteDecision(
  policy: BridgeRoutePolicy.direct,
  resolvedRoute: BridgeConnectionMode.direct,
  network: BridgeNetworkState.unknown,
  initialRoute: BridgeConnectionMode.direct,
  usedFallback: false,
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
  @override
  Future<void> activate() async {}
  static List<String>? parameters, areaParameters;
  static bool hasBookings = true;
  @override
  Future<BridgeCachedLibBookLibrariesRecord?> readLibbookLibraries({
    required BridgeConnectionMode route,
    required String day,
  }) async => BridgeCachedLibBookLibrariesRecord(
    data: const [
      BridgeLibBookLibrary(
        id: 'p1',
        name: '合成楼馆',
        freeNum: 1,
        totalNum: 2,
        storeys: [],
      ),
    ],
    sourceRoute: route,
    fetchedAt: 100,
    complete: true,
  );
  @override
  Future<BridgeCachedLibBookAreasRecord?> readLibbookAreas({
    required BridgeConnectionMode route,
    required String premisesId,
    String? storeyId,
    required String day,
  }) async {
    areaParameters = [premisesId, storeyId ?? '', day];
    return BridgeCachedLibBookAreasRecord(
      data: const [
        BridgeLibBookArea(
          id: 'a1',
          name: '合成分区',
          areaName: '',
          premisesId: 'p1',
          storeyId: 'f1',
          freeNum: 1,
          totalNum: 2,
        ),
      ],
      sourceRoute: route,
      fetchedAt: 100,
      complete: true,
    );
  }

  @override
  Future<BridgeCachedLibBookAreaDetailRecord?> readLibbookAreaDetail({
    required BridgeConnectionMode route,
    required String areaId,
  }) async => BridgeCachedLibBookAreaDetailRecord(
    data: BridgeLibBookAreaDetail(
      id: areaId,
      name: '合成分区',
      availableDates: const ['2026-09-22'],
      timeSlots: const [],
    ),
    sourceRoute: route,
    fetchedAt: 100,
    complete: true,
  );

  @override
  Future<BridgeCachedLibBookSeatsRecord?> readLibbookSeats({
    required BridgeConnectionMode route,
    required String areaId,
    required String day,
    required String startTime,
    required String endTime,
  }) async {
    parameters = [areaId, day, startTime, endTime];
    return BridgeCachedLibBookSeatsRecord(
      data: const [
        BridgeCachedLibBookSeat(
          id: 's1',
          name: '合成座位',
          no: '1',
          status: 1,
          statusName: '空闲',
        ),
      ],
      sourceRoute: route,
      fetchedAt: 100,
      complete: true,
    );
  }

  @override
  Future<BridgeCachedLibBookBookingsRecord?> readLibbookBookings({
    required BridgeConnectionMode route,
    required int page,
    required int limit,
  }) async => !hasBookings
      ? null
      : BridgeCachedLibBookBookingsRecord(
          data: BridgeCachedLibBookBookingsPage(
            bookings: const [
              BridgeCachedLibBookBooking(
                id: 'b1',
                nameMerge: '合成预约',
                areaName: '合成分区',
                seatNo: '1',
                day: '2026-09-22',
                beginTime: '08:00',
                endTime: '09:00',
                status: 1,
                statusName: '已预约',
              ),
            ],
            page: page,
            limit: limit,
            total: 21,
          ),
          sourceRoute: route,
          fetchedAt: 100,
          complete: true,
        );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  int cachedCalls = 0, plainCalls = 0;
  bool partial = false, wrongPage = false;
  int seatCalls = 0;
  @override
  Future<BridgeLibBookSeatsRefresh> libbookSeatsCached({
    required BridgeOfflineCache cache,
    required String areaId,
    required String day,
    required String startTime,
    required String endTime,
  }) async {
    seatCalls++;
    return const BridgeLibBookSeatsRefresh(
      data: [],
      route: decision,
      state: BridgeLibBookRefreshState(
        fetchedAt: 200,
        complete: true,
        savedForOffline: true,
        preservedPrevious: false,
      ),
    );
  }

  @override
  int contractVersion() => 24;
  @override
  Future<BridgeLibBookBookingsRefresh> libbookBookingsCached({
    required BridgeOfflineCache cache,
    required int page,
    required int limit,
  }) async {
    cachedCalls++;
    return BridgeLibBookBookingsRefresh(
      data: BridgeLibBookBookingsPage(
        bookings: const [],
        page: wrongPage ? 99 : page,
        limit: limit,
        total: 0,
      ),
      route: decision,
      state: BridgeLibBookRefreshState(
        fetchedAt: 200,
        complete: !partial,
        savedForOffline: !partial,
        preservedPrevious: partial,
      ),
    );
  }

  @override
  Future<BridgeRoutedLibBookBookings> libbookBookings({
    required int page,
    required int limit,
  }) async {
    plainCalls++;
    return BridgeRoutedLibBookBookings(
      data: BridgeLibBookBookingsPage(
        bookings: const [],
        page: page,
        limit: limit,
        total: 0,
      ),
      route: decision,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

part of '../bridge_backend_characterization_test.dart';

void registerCgyyPresentationTests() {
  test('研讨室保留全部时段和无时段房间，不以写资格过滤只读结果', () async {
    final client = _RoomPresentationClient();
    final result = await BridgeBackend(client).loadFeatureQuery(
      FeatureId.cgyy,
      FeatureQuery(
        view: FeatureQueryView.cgyyDayInfo,
        siteId: 7,
        date: DateTime(2026, 9, 4),
      ),
    );
    expect(result.details, hasLength(4));
    expect(result.details.first.presentation, isNotNull);
    final dynamic context = result.details.first.presentation;
    expect(context.venueSiteId, 7);
    expect(context.reservationDate, '2026-09-04');
    expect(context.availableDates, ['2026-09-04', '2026-09-05']);
    expect(context.spaces.length, 2);
    expect(context.spaces.last.spaceName, '无时段房间');
    expect(context.reservationTotalNum, 8);
    final slots = result.details.skip(1).toList();
    expect(slots.map((d) => (d.presentation as dynamic).timeId), [9, 3, 8]);
    expect(slots.map((d) => (d.presentation as dynamic).reservationStatus), [
      1,
      1,
      null,
    ]);
    expect(slots.first.action<CgyyReserveAction>()?.timeOrdinal, 0);
    expect(slots.skip(1).every((d) => d.actions.isEmpty), isTrue);
    expect(result.summary, isNot(contains('可预约时段')));
    expect(client.calls, ['cgyyDayInfo:siteId=7,date=2026-09-04']);
    expect(result.resolvedRoute, ConnectionMode.webvpn);
  });
  test('研讨室重复时段编号不取第一个标签或时间', () async {
    final result = await BridgeBackend(_RoomPresentationClient(duplicate: true))
        .loadFeatureQuery(
          FeatureId.cgyy,
          const FeatureQuery(view: FeatureQueryView.cgyyDayInfo, siteId: 7),
        );
    final item = result.details.last;
    expect(item.presentation, isNotNull);
    final dynamic p = item.presentation;
    expect(p.timeId, 8);
    expect(p.beginTime, isNull);
    expect(p.endTime, isNull);
    expect(p.timeLabel, isNull);
    expect(item.actions, isEmpty);
  });
  test('研讨室站点和用途保留typed编号与回退来源', () async {
    final backend = BridgeBackend(_CharacterizationBridgeClient());
    final sites = await backend.loadFeatureQuery(
      FeatureId.cgyy,
      FeatureQuery(date: DateTime(2026, 9, 4)),
    );
    expect(sites.details.single.presentation, isNotNull);
    final dynamic site = sites.details.single.presentation;
    expect(site.id, 7);
    expect(site.queryDate, '2026-09-04');
    expect(sites.details.single.readNavigation?.query.siteId, 7);
    final purposes = await backend.loadFeatureQuery(
      FeatureId.cgyy,
      const FeatureQuery(view: FeatureQueryView.cgyyPurposeTypes),
    );
    expect(purposes.details.single.presentation, isNotNull);
    final dynamic purpose = purposes.details.single.presentation;
    expect(purpose.key, 2);
    expect(purpose.isStaticFallback, isTrue);
  });
  test('研讨室订单投影保留原ID、取消资格及服务器页', () async {
    final backend = BridgeBackend(_CharacterizationBridgeClient());
    final result = await backend.loadFeatureQuery(
      FeatureId.cgyy,
      const FeatureQuery(view: FeatureQueryView.cgyyOrders, page: 2, size: 3),
    );
    expect(result.details.single.presentation, isNotNull);
    final dynamic p = result.details.single.presentation;
    expect(p.id, 101);
    expect(p.orderStatus, 1);
    expect(result.details.single.readNavigation?.query.orderId, 101);
    expect(
      result.details.single.action<CgyyCancelAction>()?.targetOrderId,
      101,
    );
    expect(result.pagination?.page, 2);
    expect(result.pagination?.size, 3);
  });
  test('研讨室详情和门锁仅投影公开结构', () async {
    final backend = BridgeBackend(_CharacterizationBridgeClient());
    final detail = await backend.loadFeatureQuery(
      FeatureId.cgyy,
      const FeatureQuery(view: FeatureQueryView.cgyyOrderDetail, orderId: 9),
    );
    expect(detail.details.single.presentation, isNotNull);
    final dynamic p = detail.details.single.presentation;
    expect(p.id, 9);
    expect(p.orderStatus, 2);
    expect(detail.details.single.readNavigation, isNull);
    expect(
      detail.details.single.action<CgyyCancelAction>()?.cancelledTargetOrderId,
      9,
    );
    final lock = await backend.loadFeatureQuery(
      FeatureId.cgyy,
      const FeatureQuery(view: FeatureQueryView.cgyyLockCode),
    );
    expect(lock.details.single.presentation, isNotNull);
    expect((lock.details.single.presentation as dynamic).available, isFalse);
  });
}

class _RoomPresentationClient extends _CharacterizationBridgeClient {
  _RoomPresentationClient({this.duplicate = false});
  final bool duplicate;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #cgyyDayInfo)
      return super.noSuchMethod(invocation);
    calls.add(
      'cgyyDayInfo:siteId=${invocation.namedArguments[#siteId]},date=${invocation.namedArguments[#date]}',
    );
    return Future.value(
      BridgeRoutedCgyyDayInfo(
        route: _webVpnRoute,
        data: BridgeCgyyDayInfo(
          venueSiteId: 7,
          reservationDate: '2026-09-04',
          availableDates: const ['2026-09-04', '2026-09-05'],
          reservationTotalNum: 8,
          timeSlots: [
            const BridgeCgyyTimeSlot(
              id: 9,
              beginTime: '08:00',
              endTime: '09:00',
              label: '上午',
            ),
            const BridgeCgyyTimeSlot(
              id: 3,
              beginTime: '09:00',
              endTime: '10:00',
              label: '上午',
            ),
            const BridgeCgyyTimeSlot(
              id: 8,
              beginTime: '10:00',
              endTime: '11:00',
              label: '上午',
            ),
            if (duplicate)
              const BridgeCgyyTimeSlot(
                id: 8,
                beginTime: '14:00',
                endTime: '15:00',
                label: '下午',
              ),
          ],
          spaces: const [
            BridgeCgyySpaceAvailability(
              spaceId: 4,
              spaceName: '合成研讨室',
              venueSiteId: 7,
              venueSpaceGroupId: 2,
              slots: [
                BridgeCgyySlotStatus(
                  timeId: 9,
                  reservationStatus: 1,
                  reservationEligibility: BridgeActionEligibility.allowed,
                  reservationTarget: BridgeCgyyReservationTarget(
                    venueSiteId: 7,
                    reservationDate: '2026-09-04',
                    spaceId: 4,
                    timeId: 9,
                    venueSpaceGroupId: 2,
                    timeOrdinal: 0,
                  ),
                ),
                BridgeCgyySlotStatus(
                  timeId: 3,
                  reservationStatus: 1,
                  reservationEligibility: BridgeActionEligibility.denied,
                ),
                BridgeCgyySlotStatus(
                  timeId: 8,
                  reservationEligibility: BridgeActionEligibility.unknown,
                ),
              ],
            ),
            BridgeCgyySpaceAvailability(
              spaceId: 5,
              spaceName: '无时段房间',
              venueSiteId: 7,
              slots: [],
            ),
          ],
        ),
      ),
    );
  }
}

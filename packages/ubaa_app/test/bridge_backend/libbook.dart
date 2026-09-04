part of '../bridge_backend_test.dart';

void _registerLibbookBridgeBackendTests() {
  test('BridgeBackend 在时段缺失时不调用 LibBook 座位边界', () async {
    final backend = BridgeBackend(
      _FakeLibbookSeatsClient(
        const BridgeRoutedLibBookSeats(
          data: <BridgeLibBookSeat>[],
          route: BridgeRouteDecision(
            policy: BridgeRoutePolicy.direct,
            resolvedRoute: BridgeConnectionMode.direct,
            network: BridgeNetworkState.campus,
            initialRoute: BridgeConnectionMode.direct,
            usedFallback: false,
          ),
        ),
      ),
    );

    await expectLater(
      backend.loadFeatureQuery(
        FeatureId.libbook,
        FeatureQuery(
          view: FeatureQueryView.libbookSeats,
          areaId: 'area-1',
          date: DateTime(2026, 9, 2),
          startTime: '10:00',
          endTime: '12:00',
        ),
      ),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          UbaaErrorCode.invalidInput,
        ),
      ),
    );
  });

  test('BridgeBackend 图书馆座位从 typed target 组装完整预约 action', () async {
    final response = BridgeRoutedLibBookSeats(
      data: const <BridgeLibBookSeat>[
        BridgeLibBookSeat(
          id: 'display-seat-wrong',
          name: '座位 A-01',
          no: 'A-01',
          status: 1,
          statusName: '展示文案声称不可预约',
          reserveEligibility: BridgeActionEligibility.allowed,
          reserveTarget: 'seat-authority',
        ),
      ],
      route: const BridgeRouteDecision(
        policy: BridgeRoutePolicy.direct,
        resolvedRoute: BridgeConnectionMode.direct,
        network: BridgeNetworkState.campus,
        initialRoute: BridgeConnectionMode.direct,
        usedFallback: false,
      ),
    );
    final backend = BridgeBackend(_FakeLibbookSeatsClient(response));
    final result = await backend.loadFeatureQuery(
      FeatureId.libbook,
      FeatureQuery(
        view: FeatureQueryView.libbookSeats,
        areaId: 'area-1',
        date: DateTime(2026, 9, 2),
        segment: '3',
        startTime: '10:00',
        endTime: '12:00',
      ),
    );
    final fields = {
      for (final field in result.details.single.fields)
        field.label: field.value,
    };
    expect(fields['分区 ID'], 'area-1');
    expect(fields['座位 ID'], 'display-seat-wrong');
    expect(fields['日期'], '2026-09-02');
    expect(fields['时段'], '3');
    expect(fields['状态'], '展示文案声称不可预约');
    expect(fields['可预约'], '是');
    final action = result.details.single.action<LibbookReserveAction>();
    expect(action, isNotNull);
    expect(action?.areaId, 'area-1');
    expect(action?.seatId, 'seat-authority');
    expect(action?.day, '2026-09-02');
    expect(action?.segment, '3');
    expect(action?.startTime, '10:00');
    expect(action?.endTime, '12:00');
    expect(action?.eligibility, ActionEligibility.allowed);
  });

  test('BridgeBackend 图书馆预约记录只从 typed target 组装取消 action', () async {
    final backend = BridgeBackend(
      _FakeLibbookBookingsClient(
        const BridgeRoutedLibBookBookings(
          data: BridgeLibBookBookingsPage(
            bookings: <BridgeLibBookBooking>[
              BridgeLibBookBooking(
                id: 'display-booking-wrong',
                nameMerge: '预约',
                areaName: '馆区',
                seatNo: 'A-01',
                day: '2026-09-04',
                beginTime: '10:00',
                endTime: '12:00',
                status: 1,
                statusName: '展示文案声称已结束',
                cancelEligibility: BridgeActionEligibility.allowed,
                cancelTarget: 'booking-authority',
              ),
            ],
            page: 2,
            limit: 10,
            total: 11,
          ),
          route: BridgeRouteDecision(
            policy: BridgeRoutePolicy.direct,
            resolvedRoute: BridgeConnectionMode.direct,
            network: BridgeNetworkState.campus,
            initialRoute: BridgeConnectionMode.direct,
            usedFallback: false,
          ),
        ),
      ),
    );

    final result = await backend.loadFeatureQuery(
      FeatureId.libbook,
      const FeatureQuery(
        view: FeatureQueryView.libbookBookings,
        page: 2,
        size: 10,
      ),
    );
    final action = result.details.single.action<LibbookCancelAction>();
    expect(action, isNotNull);
    expect(action?.bookingId, 'booking-authority');
    expect(action?.page, 2);
    expect(action?.limit, 10);
    expect(action?.eligibility, ActionEligibility.allowed);
  });

  test('BridgeBackend 不用展示状态名替代缺失的 typed 取消资格', () async {
    final backend = BridgeBackend(
      _FakeLibbookBookingsClient(
        const BridgeRoutedLibBookBookings(
          data: BridgeLibBookBookingsPage(
            bookings: <BridgeLibBookBooking>[
              BridgeLibBookBooking(
                id: 'booking-unknown',
                nameMerge: '预约',
                areaName: '馆区',
                seatNo: 'A-02',
                day: '2026-09-04',
                beginTime: '12:00',
                endTime: '14:00',
                status: null,
                statusName: '展示文案声称可以取消',
                cancelEligibility: BridgeActionEligibility.unknown,
                cancelTarget: null,
              ),
            ],
            page: 2,
            limit: 10,
            total: 1,
          ),
          route: BridgeRouteDecision(
            policy: BridgeRoutePolicy.direct,
            resolvedRoute: BridgeConnectionMode.direct,
            network: BridgeNetworkState.campus,
            initialRoute: BridgeConnectionMode.direct,
            usedFallback: false,
          ),
        ),
      ),
    );

    final result = await backend.loadFeatureQuery(
      FeatureId.libbook,
      const FeatureQuery(
        view: FeatureQueryView.libbookBookings,
        page: 2,
        size: 10,
      ),
    );

    expect(result.details.single.action<LibbookCancelAction>(), isNull);
  });
}

class _FakeLibbookSeatsClient extends _CompatibleBridgeClient {
  _FakeLibbookSeatsClient(this.response);

  final BridgeRoutedLibBookSeats response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #libbookSeats) {
      final named = invocation.namedArguments;
      expect(named[#areaId], 'area-1');
      expect(named[#day], '2026-09-02');
      expect(named[#startTime], '10:00');
      expect(named[#endTime], '12:00');
      return Future<BridgeRoutedLibBookSeats>.value(response);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

class _FakeLibbookBookingsClient extends _CompatibleBridgeClient {
  _FakeLibbookBookingsClient(this.response);

  final BridgeRoutedLibBookBookings response;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #libbookBookings) {
      final named = invocation.namedArguments;
      expect(named[#page], 2);
      expect(named[#limit], 10);
      return Future<BridgeRoutedLibBookBookings>.value(response);
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

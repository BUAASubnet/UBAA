part of '../bridge_backend_test.dart';

void _registerCgyyBridgeBackendTests() {
  test('BridgeBackend 场馆预约入口独立拒绝不完整或不一致的 typed actions', () async {
    final client = _RecordingCgyyPrepareClient();
    final backend = BridgeBackend(client);
    const first = CgyyReserveAction(
      venueSiteId: 3,
      reservationDate: '2026-09-03',
      spaceId: 4,
      timeId: 5,
      venueSpaceGroupId: 9,
      timeOrdinal: 0,
      eligibility: ActionEligibility.allowed,
    );
    const second = CgyyReserveAction(
      venueSiteId: 3,
      reservationDate: '2026-09-03',
      spaceId: 4,
      timeId: 6,
      venueSpaceGroupId: 9,
      timeOrdinal: 1,
      eligibility: ActionEligibility.allowed,
    );
    final invalidActions = <List<CgyyReserveAction>>[
      const <CgyyReserveAction>[],
      const <CgyyReserveAction>[
        CgyyReserveAction(
          venueSiteId: 3,
          reservationDate: '2026-09-03',
          spaceId: 4,
          timeId: 5,
          venueSpaceGroupId: 9,
          timeOrdinal: 0,
          eligibility: ActionEligibility.denied,
        ),
      ],
      const <CgyyReserveAction>[
        first,
        CgyyReserveAction(
          venueSiteId: 3,
          reservationDate: '2026-09-04',
          spaceId: 4,
          timeId: 6,
          venueSpaceGroupId: 9,
          timeOrdinal: 1,
          eligibility: ActionEligibility.allowed,
        ),
      ],
      const <CgyyReserveAction>[first, first],
      const <CgyyReserveAction>[
        first,
        CgyyReserveAction(
          venueSiteId: 3,
          reservationDate: '2026-09-03',
          spaceId: 4,
          timeId: 7,
          venueSpaceGroupId: 9,
          timeOrdinal: 2,
          eligibility: ActionEligibility.allowed,
        ),
      ],
      const <CgyyReserveAction>[
        CgyyReserveAction(
          venueSiteId: 3,
          reservationDate: '2026-09-03',
          spaceId: 4,
          timeId: 5,
          venueSpaceGroupId: 0,
          timeOrdinal: 0,
          eligibility: ActionEligibility.allowed,
        ),
      ],
    ];

    for (final actions in invalidActions) {
      await expectLater(
        backend.prepareCgyySubmitReservation(
          _bridgeCgyyInput(actions: actions),
        ),
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            'code',
            UbaaErrorCode.invalidInput,
          ),
        ),
      );
    }
    expect(client.prepareCalls, 0);

    await backend.prepareCgyySubmitReservation(
      _bridgeCgyyInput(actions: const <CgyyReserveAction>[second, first]),
    );
    expect(client.prepareCalls, 1);
    expect(
      client.request?.selections.map((selection) => selection.timeId),
      <int>[5, 6],
    );
  });

  test('BridgeBackend 场馆取消只向 FRB 传 canonical 正整数订单 ID', () async {
    final client = _RecordingCgyyCancelPrepareClient();
    final backend = BridgeBackend(client);

    for (final id in <int>[0, -1]) {
      await expectLater(
        backend.prepareCgyyCancelOrder(id: id),
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            'code',
            UbaaErrorCode.invalidInput,
          ),
        ),
      );
    }
    expect(client.prepareCalls, 0);

    final intent = await backend.prepareCgyyCancelOrder(id: 17);
    expect(client.prepareCalls, 1);
    expect(client.request?.orderId, 17);
    expect(intent.readbackQuery?.view, FeatureQueryView.cgyyOrderDetail);
    expect(intent.readbackQuery?.orderId, 17);
  });

  test('BridgeBackend 场馆取消双回读把 0-based 分页与固定路线 typed 传入 FRB', () async {
    final client = _RecordingCgyyReadbackClient();
    final backend = BridgeBackend(client);

    final orders = await backend.loadCgyyOrdersOnRoute(
      route: ConnectionMode.webvpn,
      page: 0,
      size: 20,
    );
    final detail = await backend.loadCgyyOrderDetailOnRoute(
      route: ConnectionMode.webvpn,
      orderId: 17,
    );

    expect(client.routes, const <BridgeConnectionMode>[
      BridgeConnectionMode.webVpn,
      BridgeConnectionMode.webVpn,
    ]);
    expect(client.page, 0);
    expect(client.size, 20);
    expect(client.orderId, 17);
    expect(orders.resolvedRoute, ConnectionMode.webvpn);
    expect(detail.resolvedRoute, ConnectionMode.webvpn);
    expect(orders.pagination?.page, 1);
    expect(
      orders.details.single.action<CgyyCancelAction>()?.cancelledTargetOrderId,
      17,
    );
    expect(
      detail.details.single.action<CgyyCancelAction>()?.cancelledTargetOrderId,
      17,
    );
  });
}

class _RecordingCgyyPrepareClient extends _CompatibleBridgeClient {
  int prepareCalls = 0;
  BridgeCgyySubmitReservationRequest? request;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #prepareCgyySubmitReservation) {
      prepareCalls += 1;
      request =
          invocation.namedArguments[#request]
              as BridgeCgyySubmitReservationRequest;
      return Future<BridgeWriteIntent>.value(
        _writeIntent(BridgeWriteOperation.cgyySubmitReservation),
      );
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

class _RecordingCgyyCancelPrepareClient extends _CompatibleBridgeClient {
  int prepareCalls = 0;
  BridgeCgyyCancelOrderRequest? request;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #prepareCgyyCancelOrder) {
      prepareCalls += 1;
      request =
          invocation.namedArguments[#request] as BridgeCgyyCancelOrderRequest;
      return Future<BridgeWriteIntent>.value(
        _writeIntent(BridgeWriteOperation.cgyyCancelOrder),
      );
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

class _RecordingCgyyReadbackClient extends _CompatibleBridgeClient {
  final List<BridgeConnectionMode> routes = <BridgeConnectionMode>[];
  int? page;
  int? size;
  int? orderId;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #cgyyOrdersOnRoute) {
      routes.add(invocation.namedArguments[#route] as BridgeConnectionMode);
      page = invocation.namedArguments[#page] as int;
      size = invocation.namedArguments[#size] as int;
      return Future<BridgeCallerPinnedCgyyOrders>.value(
        const BridgeCallerPinnedCgyyOrders(
          data: BridgeCgyyOrdersPage(
            content: <BridgeCgyyOrder>[_cancelledBridgeOrder],
            totalElements: 1,
            totalPages: 1,
            size: 20,
            number: 0,
          ),
          pinnedRoute: BridgeConnectionMode.webVpn,
        ),
      );
    }
    if (invocation.memberName == #cgyyOrderDetailOnRoute) {
      routes.add(invocation.namedArguments[#route] as BridgeConnectionMode);
      orderId = invocation.namedArguments[#id] as int;
      return Future<BridgeCallerPinnedCgyyOrder>.value(
        const BridgeCallerPinnedCgyyOrder(
          data: _cancelledBridgeOrder,
          pinnedRoute: BridgeConnectionMode.webVpn,
        ),
      );
    }
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

const _cancelledBridgeOrder = BridgeCgyyOrder(
  id: 17,
  orderStatus: 2,
  checkStatus: 2,
  cancelEligibility: BridgeActionEligibility.denied,
  cancelledTarget: BridgeCgyyCancelOrderTarget(orderId: 17),
);

CgyySubmitInput _bridgeCgyyInput({required List<CgyyReserveAction> actions}) =>
    CgyySubmitInput(
      actions: actions,
      phone: 'phone-placeholder',
      theme: '讨论',
      purposeType: 1,
      joinerNum: 2,
      activityContent: '课程讨论',
      joiners: '张三',
      isPhilosophySocialSciences: false,
      isOffSchoolJoiner: false,
    );

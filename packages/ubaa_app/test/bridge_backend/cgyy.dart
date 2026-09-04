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

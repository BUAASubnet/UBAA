part of '../bridge_backend_test.dart';

void _registerYgdkBridgeBackendTests() {
  test('BridgeBackend 在构造 Uint8List 前拒绝非 canonical 阳光打卡输入', () async {
    final client = _CountingYgdkPrepareClient();
    final backend = BridgeBackend(client);
    final invalidInputs = <YgdkSubmitInput>[
      _bridgeYgdkInput(
        action: const YgdkSubmitAction(
          classifyId: 31,
          itemId: 7,
          eligibility: ActionEligibility.denied,
        ),
      ),
      _bridgeYgdkInput(
        action: const YgdkSubmitAction(
          classifyId: 31,
          itemId: 7,
          eligibility: ActionEligibility.unknown,
        ),
      ),
      _bridgeYgdkInput(
        action: const YgdkSubmitAction(
          classifyId: 0,
          itemId: 7,
          eligibility: ActionEligibility.allowed,
        ),
      ),
      _bridgeYgdkInput(
        action: const YgdkSubmitAction(
          classifyId: 31,
          itemId: 0,
          eligibility: ActionEligibility.allowed,
        ),
      ),
      _bridgeYgdkInput(startTime: '09:00'),
      _bridgeYgdkInput(startTime: ' 2026-09-01 09:00'),
      _bridgeYgdkInput(endTime: '2026-09-02 10:00'),
      _bridgeYgdkInput(endTime: '2026-09-01 09:00'),
      _bridgeYgdkInput(photoBytes: const <int>[-1]),
      _bridgeYgdkInput(photoBytes: const <int>[256]),
      _bridgeYgdkInput(fileName: '../safe.jpg'),
      _bridgeYgdkInput(fileName: ' safe.jpg'),
      _bridgeYgdkInput(mimeType: 'IMAGE/JPEG'),
      _bridgeYgdkInput(mimeType: 'image/jpeg '),
    ];

    for (final input in invalidInputs) {
      await expectLater(
        backend.prepareYgdkSubmit(input),
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
  });
}

YgdkSubmitInput _bridgeYgdkInput({
  YgdkSubmitAction action = const YgdkSubmitAction(
    classifyId: 31,
    itemId: 7,
    eligibility: ActionEligibility.allowed,
  ),
  String startTime = '2026-09-01 09:00',
  String endTime = '2026-09-01 10:00',
  List<int> photoBytes = const <int>[1],
  String fileName = 'safe.jpg',
  String mimeType = 'image/jpeg',
}) => YgdkSubmitInput(
  action: action,
  startTime: startTime,
  endTime: endTime,
  place: '校园',
  shareToSquare: false,
  photo: YgdkPhotoInput(
    bytes: photoBytes,
    fileName: fileName,
    mimeType: mimeType,
  ),
);

final class _CountingYgdkPrepareClient extends _CompatibleBridgeClient {
  int prepareCalls = 0;

  @override
  Future<BridgeWriteIntent> prepareYgdkSubmit({
    required BridgeYgdkSubmitRequest request,
  }) async {
    prepareCalls++;
    return _writeIntent(BridgeWriteOperation.ygdkSubmit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('unexpected bridge call: ${invocation.memberName}');
  }
}

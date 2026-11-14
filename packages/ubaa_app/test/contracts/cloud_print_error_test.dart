import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../support/bridge/fixtures.dart' show FixtureContractVersionClient;

void main() {
  test('云打印整批错误将实际路线和重试限制传到页面', () async {
    for (final (bridgeRoute, route) in [
      (BridgeConnectionMode.direct, ConnectionMode.direct),
      (BridgeConnectionMode.webVpn, ConnectionMode.webvpn),
      (null, null),
    ]) {
      final backend = BridgeBackend(_Client(bridgeRoute));
      await expectLater(
        backend.cloudPrint.documents(scans: false),
        throwsA(
          isA<UiError>()
              .having((error) => error.code, '错误码', UbaaErrorCode.networkError)
              .having((error) => error.resolvedRoute, '实际路线', route)
              .having((error) => error.retryable, '可重试性', true),
        ),
      );
      await backend.dispose();
    }
  });

  test('云打印逐项未知结果保留网关路线并禁止自动重试', () async {
    final backend = BridgeBackend(_Client(BridgeConnectionMode.webVpn));
    final results = await backend.cloudPrint.delete(['15', '16'], scans: false);
    expect(results[0], isNull);
    expect(results[1]!.code, UbaaErrorCode.outcomeUnknown);
    expect(results[1]!.resolvedRoute, ConnectionMode.webvpn);
    expect(results[1]!.retryable, isFalse);
    await backend.dispose();
  });
}

class _Client extends FixtureContractVersionClient {
  _Client(this.route) : super(66);
  final BridgeConnectionMode? route;

  @override
  Future<List<BridgePrintDocument>> cloudPrintDocuments({
    required bool scans,
  }) async {
    throw BridgeError(
      code: BridgeErrorCode.networkError,
      kind: BridgeErrorKind.network,
      retryable: true,
      message: '合成网络错误',
      resolvedRoute: route,
    );
  }

  @override
  Future<List<BridgeError?>> cloudPrintDelete({
    required bool scans,
    required List<String> ids,
  }) async => [
    null,
    BridgeError(
      code: BridgeErrorCode.outcomeUnknown,
      kind: BridgeErrorKind.network,
      retryable: false,
      message: '请核对合成结果',
      resolvedRoute: route,
    ),
  ];
}

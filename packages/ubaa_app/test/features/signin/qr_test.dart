import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../support/bridge/fixtures.dart';

void main() {
  test('读取二维码每次传递排课与毫秒偏移并保留服务器结果', () async {
    final client = _SigninQrClient();
    final backend = BridgeBackend(client);
    final live = await backend.fetchSigninQr('course-1', Duration.zero);
    final saved = await backend.fetchSigninQr(
      'course-1',
      const Duration(seconds: 2),
    );
    expect(client.requests, [('course-1', 0), ('course-1', 2000)]);
    expect(live.timestamp, 1700000000000);
    expect(saved.timestamp, 1700000003000);
    expect(
      Uri.parse(saved.content).queryParameters['timestamp'],
      '1700000003000',
    );
  });

  test('非法偏移不越过 FFI；Bridge 认证错误保留稳定分类', () async {
    final client = _SigninQrClient();
    final backend = BridgeBackend(client);
    for (final offset in [
      const Duration(microseconds: -1),
      const Duration(milliseconds: 60001),
    ]) {
      await expectLater(
        backend.fetchSigninQr('course-1', offset),
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            'code',
            UbaaErrorCode.invalidInput,
          ),
        ),
      );
    }
    expect(client.requests, isEmpty);
    client.requiresAuth = true;
    await expectLater(
      backend.fetchSigninQr('course-1', Duration.zero),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          UbaaErrorCode.authenticationRequired,
        ),
      ),
    );
  });
}

final class _SigninQrClient extends FixtureContractVersionClient {
  _SigninQrClient() : super(currentBridgeContractVersion);

  final requests = <(String, int)>[];
  bool requiresAuth = false;

  @override
  Future<BridgeRoutedSigninQr> signinQr({
    required String courseId,
    required int offsetMs,
  }) async {
    requests.add((courseId, offsetMs));
    if (requiresAuth) {
      throw const BridgeError(
        code: BridgeErrorCode.authenticationRequired,
        kind: BridgeErrorKind.authentication,
        retryable: false,
        message: '需要认证',
      );
    }
    final timestamp = 1700000000000 + (requests.length - 1) * 1000 + offsetMs;
    return BridgeRoutedSigninQr(
      data: BridgeSigninQr(
        content:
            'http://iclass.buaa.edu.cn:8081/eschool/app/course/stu_scan_sign.action?courseSchedId=$courseId&timestamp=$timestamp',
        timestamp: timestamp,
      ),
      route: const BridgeRouteDecision(
        policy: BridgeRoutePolicy.direct,
        resolvedRoute: BridgeConnectionMode.direct,
        network: BridgeNetworkState.campus,
        initialRoute: BridgeConnectionMode.direct,
        usedFallback: false,
      ),
    );
  }
}

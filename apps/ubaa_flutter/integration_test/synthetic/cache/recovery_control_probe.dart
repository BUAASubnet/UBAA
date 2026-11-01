import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';

/// 真实 FFI 验证控制柄的同步撤销与过期；均在 Core 路线解析前拒绝。
Future<void> probeRecoveryControl(BridgeClient client) async {
  for (final expired in [true, false]) {
    final control = BridgeRequiredRecoveryControl(
      timeoutMillis: expired ? 0 : 10000,
    );
    try {
      if (!expired) control.cancel();
      await expectLater(
        client.recoverRequiredSessionControlled(
          feature: BridgeRecoveryFeature.schedule,
          control: control,
        ),
        throwsA(
          isA<BridgeError>()
              .having(
                (error) => error.code,
                '控制范围的稳定分类',
                expired
                    ? BridgeErrorCode.timeout
                    : BridgeErrorCode.operationConflict,
              )
              .having((error) => error.retryable, '不自动重试', isFalse),
        ),
      );
    } finally {
      control.dispose();
    }
  }
  // 已取消操作不能释放或注销共享客户端；后续本机配置仍可查询。
  expect(await client.routeSettings(), isA<BridgeRouteSettings>());
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('登录原因生成具体提示且不改变重试和凭据错误码', () {
    final error = const UiErrorMapper().fromCore(
      const CoreErrorPayload(
        code: 'upstream_changed',
        retryable: false,
        authStage: AuthFailureStage.captcha,
        authReason: AuthFailureReason.verificationIncomplete,
      ),
    );
    expect(error.title, '登录验证未通过');
    expect(error.code, UbaaErrorCode.upstreamChanged);
    expect(error.retryable, isFalse);
    expect(error.withIssueId('UBAA-test').authReason, error.authReason);
    final restored = mapCoreErrorJson(uiErrorToJson(error));
    expect(restored.authReason, error.authReason);
    expect(restored.authStage, error.authStage);
    expect(AuthFailureReason.parse('任意原始文字'), isNull);
    expect(AuthFailureStage.parse('https://example.test'), isNull);
  });

  test('CLI 失败 envelope 保留实际路线且可安全序列化往返', () {
    final payload = CoreErrorPayload.fromJson({
      'ok': false,
      'error': {'code': 'parse_error', 'kind': 'parse', 'retryable': false},
      'meta': {'resolvedRoute': 'webvpn'},
    });
    expect(payload.resolvedRoute, ConnectionMode.webvpn);
    final error = mapCoreErrorJson(payload.toJson());
    expect(error.resolvedRoute, ConnectionMode.webvpn);
    expect(error.kind, UbaaErrorKind.parse);
    expect(
      mapCoreErrorJson(uiErrorToJson(error)).resolvedRoute,
      ConnectionMode.webvpn,
    );
  });

  test('结果未知即使外部错误标志错误也不能启用通用重试', () {
    final error = mapCoreError(code: 'outcome_unknown', retryable: true);
    expect(error.retryable, isFalse);
    expect(error.actionLabel, '刷新状态');
  });

  test('调试详情也不能保留短个人资料或原始响应', () {
    for (final message in ['姓名：示例用户，学号：2099000000', '{"data":"原始正文"}']) {
      final error = mapCoreError(
        code: 'internal_error',
        message: message,
        includeTechnicalDetail: true,
      );
      expect(error.technicalDetail, isNull);
    }
  });
}

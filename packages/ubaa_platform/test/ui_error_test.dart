import 'dart:async';

import 'package:test/test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  group('UiErrorMapper', () {
    test('映射 Core 错误码并使用安全中文文案', () {
      final error = mapCoreError(
        code: 'invalid_credentials',
        kind: 'authentication',
        retryable: false,
        message: 'upstream password=secret',
      );

      expect(error.code, UbaaErrorCode.invalidCredentials);
      expect(error.retryable, isFalse);
      expect(error.title, '登录失败');
      expect(error.message, '账号或密码不正确');
      expect(error.message, isNot(contains('secret')));
      expect(error.technicalDetail, isNull);
    });

    test('结果未知缺少重试标记时仍默认禁止重试', () {
      final error = mapCoreError(code: 'outcome_unknown');

      expect(error.code, UbaaErrorCode.outcomeUnknown);
      expect(error.retryable, isFalse);
      expect(error.actionLabel, '刷新状态');
    });

    test('历史 schema-v8 envelope 仍可读取嵌套 error', () {
      final error = mapCoreErrorJson({
        'schemaVersion': 8,
        'ok': false,
        'error': {
          'code': 'timeout',
          'kind': 'network',
          'retryable': true,
          'message': 'GET https://secret.example',
        },
      });

      expect(error.code, UbaaErrorCode.timeout);
      expect(error.retryable, isTrue);
      expect(error.actionLabel, '重试');
    });

    test('历史 schema-v3 error envelope 保持安全兼容', () {
      final error = mapCoreErrorJson({
        'schemaVersion': 3,
        'ok': false,
        'error': {'code': 'timeout', 'kind': 'network', 'retryable': true},
      });

      expect(error.code, UbaaErrorCode.timeout);
      expect(error.retryable, isTrue);
    });

    test('未知或畸形载荷归约为内部错误', () {
      final error = mapCoreErrorJson(const {'unexpected': 'value'});

      expect(error.code, UbaaErrorCode.internalError);
      expect(error.message, '应用内部错误，请稍后重试');
    });

    test('平台超时和网络异常映射为可重试错误', () {
      final mapper = UiErrorMapper();
      final timeout = mapper.fromException(TimeoutException('timed out'));
      final network = mapper.fromException(_FakeSocketException());

      expect(timeout.code, UbaaErrorCode.timeout);
      expect(network.code, UbaaErrorCode.networkError);
      expect(timeout.retryable, isTrue);
      expect(network.retryable, isTrue);
    });

    test('诊断细节仅接受脱敏短文本，issue id 有界', () {
      final error = mapCoreError(
        code: 'internal_error',
        message: 'safe diagnostic',
        issueId: 'issue_123',
        includeTechnicalDetail: true,
      );
      final rejected = mapCoreError(
        code: 'internal_error',
        message: 'token=secret',
        issueId: 'not safe!',
        includeTechnicalDetail: true,
      );

      expect(error.technicalDetail, 'safe diagnostic');
      expect(error.issueId, 'issue_123');
      expect(rejected.technicalDetail, isNull);
      expect(rejected.issueId, isNull);
    });

    test('wire 投影不包含诊断字段', () {
      final error = mapCoreError(
        code: 'network_error',
        message: 'safe diagnostic',
        issueId: 'issue_1',
        includeTechnicalDetail: true,
      );

      expect(uiErrorToJson(error), <String, Object?>{
        'code': 'network_error',
        'retryable': true,
        'message': '请检查网络连接后重试',
        'issueId': 'issue_1',
      });
    });
  });
}

class _FakeSocketException implements Exception {
  @override
  String toString() => 'SocketException(token=secret)';
}

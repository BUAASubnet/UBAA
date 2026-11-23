import 'dart:async';

import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart' show ErrorDiagnostic;
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  group('UiErrorMapper', () {
    test('图书馆 WebVPN 路线拒绝给出切换提示', () {
      final error = const UiErrorMapper().fromCore(
        CoreErrorPayload(
          code: 'permission_denied',
          diagnostic: ErrorDiagnostic.parse(
            '{"source":"crates/ubaa_core/src/facade/routing.rs:1","stage":"route","reason":"library_webvpn_unsupported"}',
          ),
        ),
      );
      expect(error.message, '图书馆借阅暂不支持 WebVPN，请切换为自动或直连');
    });
    test('续借复核按原因显示不可续借或目标已变化', () {
      for (final (code, reason, message) in [
        ('invalid_input', 'library_renew_unavailable', '这本书当前不可续借，请刷新后查看借阅记录'),
        ('operation_conflict', 'library_renew_changed', '续借目标已变化，请刷新后重试'),
      ]) {
        final error = const UiErrorMapper().fromCore(
          CoreErrorPayload(
            code: code,
            diagnostic: ErrorDiagnostic.parse(
              '{"source":"crates/ubaa_core/src/features/campus/library_loans.rs:1","stage":"preflight","reason":"$reason"}',
            ),
          ),
        );
        expect(error.message, message);
      }
    });
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

    test('上游响应不匹配使用中性提示', () {
      final error = mapCoreError(
        code: 'upstream_changed',
        kind: 'upstream',
        retryable: false,
        message: 'ignored upstream detail',
      );

      expect(error.title, '暂时无法完成操作');
      expect(error.message, '应用无法处理学校返回的信息，请到「设置 › 诊断信息」分享完整诊断');
      expect(error.actionLabel, isNull);
      expect(error.retryable, isFalse);
    });

    test('图书馆非预约时段保留安全文案并允许重试', () {
      final error = const UiErrorMapper().fromCore(
        CoreErrorPayload(
          code: 'business_unavailable',
          kind: 'upstream',
          retryable: true,
          diagnostic: ErrorDiagnostic.parse(
            '{"source":"crates/ubaa_core/src/features/libbook/parser.rs:96",'
            '"stage":"response","reason":"outside_reservation_hours"}',
          ),
        ),
      );

      expect(error.code, UbaaErrorCode.businessUnavailable);
      expect(error.title, '预约暂不可用');
      expect(error.message, '当前无法预约，请稍后刷新');
      expect(error.actionLabel, '重试');
      expect(error.retryable, isTrue);
    });

    test('云打印服务不可用与图书馆预约时段使用不同的恢复建议', () {
      final error = mapCoreError(code: 'business_unavailable');
      expect(error.code, UbaaErrorCode.businessUnavailable);
      expect(error.message, '当前无法使用此服务，请稍后重试');
      expect(error.retryable, isTrue);
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
      expect(error.message, '出现异常，请稍后重试');
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

    test('不保留原始错误文本，且 issue id 有界', () {
      final error = mapCoreError(
        code: 'internal_error',
        message: 'safe diagnostic',
        issueId: 'issue_123',
      );
      final rejected = mapCoreError(
        code: 'internal_error',
        message: 'token=secret',
        issueId: 'not safe!',
      );

      expect(error.technicalDetail, isNull);
      expect(error.issueId, 'issue_123');
      expect(rejected.technicalDetail, isNull);
      expect(rejected.issueId, isNull);
    });

    test('wire 投影不包含诊断字段', () {
      final error = mapCoreError(
        code: 'network_error',
        message: 'safe diagnostic',
        issueId: 'issue_1',
      );

      expect(uiErrorToJson(error), <String, Object?>{
        'code': 'network_error',
        'retryable': true,
        'message': '请检查网络连接后重试',
        'issueId': 'issue_1',
        'kind': 'network',
      });
    });
  });
}

class _FakeSocketException implements Exception {
  @override
  String toString() => 'SocketException(token=secret)';
}

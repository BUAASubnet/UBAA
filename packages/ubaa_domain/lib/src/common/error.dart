import 'package:meta/meta.dart';

/// 稳定错误代码。值与 Rust Core/CLI 合同保持一致，UI 不直接展示上游文本。
enum UbaaErrorCode {
  invalidInput,
  authenticationRequired,
  invalidCredentials,
  passwordRiskConfirmationFailed,
  permissionDenied,
  networkError,
  timeout,
  upstreamUnavailable,
  upstreamChanged,
  parseError,
  internalError,
  unsupported,
  confirmationRequired,
  intentExpired,
  operationConflict,
  outcomeUnknown,
}

extension UbaaErrorCodeText on UbaaErrorCode {
  String get wireName => switch (this) {
    UbaaErrorCode.invalidInput => 'invalid_input',
    UbaaErrorCode.authenticationRequired => 'authentication_required',
    UbaaErrorCode.invalidCredentials => 'invalid_credentials',
    UbaaErrorCode.passwordRiskConfirmationFailed =>
      'password_risk_confirmation_failed',
    UbaaErrorCode.permissionDenied => 'permission_denied',
    UbaaErrorCode.networkError => 'network_error',
    UbaaErrorCode.timeout => 'timeout',
    UbaaErrorCode.upstreamUnavailable => 'upstream_unavailable',
    UbaaErrorCode.upstreamChanged => 'upstream_changed',
    UbaaErrorCode.parseError => 'parse_error',
    UbaaErrorCode.internalError => 'internal_error',
    UbaaErrorCode.unsupported => 'unsupported',
    UbaaErrorCode.confirmationRequired => 'confirmation_required',
    UbaaErrorCode.intentExpired => 'intent_expired',
    UbaaErrorCode.operationConflict => 'operation_conflict',
    UbaaErrorCode.outcomeUnknown => 'outcome_unknown',
  };
}

/// 面向用户的安全错误模型。
///
/// `technicalDetail` 只允许在开发日志中使用，不能直接渲染到界面或遥测。
@immutable
class UiError {
  const UiError({
    required this.code,
    required this.title,
    required this.message,
    this.actionLabel,
    this.retryable = false,
    this.issueId,
    this.technicalDetail,
  });

  final UbaaErrorCode code;
  final String title;
  final String message;
  final String? actionLabel;
  final bool retryable;
  final String? issueId;

  /// 不得包含密码、Cookie、URL、上游响应正文或个人信息。
  final String? technicalDetail;

  @override
  String toString() => 'UiError(${code.wireName}, retryable: $retryable)';
}

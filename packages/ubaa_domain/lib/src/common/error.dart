import 'package:meta/meta.dart';

import 'route.dart';

/// 登录诊断只接受固定阶段和原因，不携带学校返回的文字。
enum AuthFailureStage {
  loginPage('login_page'),
  submission('submission'),
  redirect('redirect'),
  captcha('captcha'),
  identityValidation('identity_validation');

  const AuthFailureStage(this.wireName);
  final String wireName;
  static AuthFailureStage? parse(String? value) {
    for (final stage in values) {
      if (stage.wireName == value) return stage;
    }
    return null;
  }
}

enum AuthFailureReason {
  loginPageInvalid('login_page_invalid'),
  redirectInvalid('redirect_invalid'),
  identityResponseInvalid('identity_response_invalid'),
  identityMismatch('identity_mismatch'),
  captchaExpired('captcha_expired'),
  verificationIncomplete('verification_incomplete');

  const AuthFailureReason(this.wireName);
  final String wireName;
  static AuthFailureReason? parse(String? value) {
    for (final reason in values) {
      if (reason.wireName == value) return reason;
    }
    return null;
  }
}

/// 本地启动原因只接受枚举，不接受路径或异常正文。
enum InitializationFailure {
  configuration,
  session,
  resourceBusy,
  bridgeIncompatible,
  componentUnavailable,
}

final class InitializationException implements Exception {
  const InitializationException(this.failure);
  final InitializationFailure failure;
  @override
  String toString() => 'InitializationException(${failure.name})';
}

/// 错误类别属于共享领域模型，平台与应用层使用同一个类型。
enum UbaaErrorKind {
  input,
  authentication,
  network,
  upstream,
  parse,
  internal,
  unknown,
}

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
  businessUnavailable,
  upstreamChanged,
  parseError,
  internalError,
  unsupported,
  confirmationRequired,
  intentExpired,
  operationConflict,
  outcomeUnknown,
  updateRequired,
}

/// 更新门控的默认提示；页面可根据当前交互补充说明。
const appUpdateRequiredMessage = '请更新应用后再使用学校功能';

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
    UbaaErrorCode.businessUnavailable => 'business_unavailable',
    UbaaErrorCode.upstreamChanged => 'upstream_changed',
    UbaaErrorCode.parseError => 'parse_error',
    UbaaErrorCode.internalError => 'internal_error',
    UbaaErrorCode.unsupported => 'unsupported',
    UbaaErrorCode.confirmationRequired => 'confirmation_required',
    UbaaErrorCode.intentExpired => 'intent_expired',
    UbaaErrorCode.operationConflict => 'operation_conflict',
    UbaaErrorCode.outcomeUnknown => 'outcome_unknown',
    UbaaErrorCode.updateRequired => 'update_required',
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
    this.kind = UbaaErrorKind.unknown,
    this.resolvedRoute,
    this.initializationFailure,
    this.authStage,
    this.authReason,
  });

  final UbaaErrorCode code;
  final String title;
  final String message;
  final String? actionLabel;
  final bool retryable;
  final String? issueId;
  final UbaaErrorKind kind;

  /// 本次失败的实际路线，不能用配置策略或上一份成功快照代替。
  final ConnectionMode? resolvedRoute;
  final InitializationFailure? initializationFailure;
  final AuthFailureStage? authStage;
  final AuthFailureReason? authReason;

  /// 不得包含密码、Cookie、URL、上游响应正文或个人信息。
  final String? technicalDetail;

  /// 附加本地诊断编号时完整保留 Core 的错误语义。
  UiError withIssueId(String value) => UiError(
    code: code,
    title: title,
    message: message,
    actionLabel: actionLabel,
    retryable: retryable,
    issueId: value,
    kind: kind,
    resolvedRoute: resolvedRoute,
    technicalDetail: technicalDetail,
    initializationFailure: initializationFailure,
    authStage: authStage,
    authReason: authReason,
  );

  @override
  String toString() => 'UiError(${code.wireName}, retryable: $retryable)';
}

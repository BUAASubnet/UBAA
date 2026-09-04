import 'package:ubaa_domain/ubaa_domain.dart';

/// 将 Core 稳定错误代码映射为不泄露上游细节的中文提示。
class UbaaErrorMapper {
  const UbaaErrorMapper._();

  static UiError fromCode(UbaaErrorCode code) => switch (code) {
    UbaaErrorCode.invalidInput => const UiError(
      code: UbaaErrorCode.invalidInput,
      title: '输入有误',
      message: '请检查学号、密码和其他必填内容。',
    ),
    UbaaErrorCode.authenticationRequired => const UiError(
      code: UbaaErrorCode.authenticationRequired,
      title: '登录已失效',
      message: '请重新登录后再试。',
      actionLabel: '重新登录',
    ),
    UbaaErrorCode.invalidCredentials => const UiError(
      code: UbaaErrorCode.invalidCredentials,
      title: '账号或密码不正确',
      message: '请确认学号和密码后重试。',
    ),
    UbaaErrorCode.passwordRiskConfirmationFailed => const UiError(
      code: UbaaErrorCode.passwordRiskConfirmationFailed,
      title: '需要额外确认',
      message: '学校登录需要额外安全确认，暂时无法完成。',
    ),
    UbaaErrorCode.permissionDenied => const UiError(
      code: UbaaErrorCode.permissionDenied,
      title: '暂无权限',
      message: '当前账号没有使用此功能的权限。',
    ),
    UbaaErrorCode.networkError => const UiError(
      code: UbaaErrorCode.networkError,
      title: '网络不可用',
      message: '请检查校园网或 VPN 连接后重试。',
      actionLabel: '重试',
      retryable: true,
    ),
    UbaaErrorCode.timeout => const UiError(
      code: UbaaErrorCode.timeout,
      title: '请求超时',
      message: '网络响应较慢，请稍后重试。',
      actionLabel: '重试',
      retryable: true,
    ),
    UbaaErrorCode.upstreamUnavailable => const UiError(
      code: UbaaErrorCode.upstreamUnavailable,
      title: '学校服务暂时不可用',
      message: '请稍后重试；其他功能可能仍然可以使用。',
      actionLabel: '重试',
      retryable: true,
    ),
    UbaaErrorCode.upstreamChanged || UbaaErrorCode.parseError => const UiError(
      code: UbaaErrorCode.upstreamChanged,
      title: '学校系统发生变化',
      message: '暂时无法读取此功能，请稍后再试。',
      actionLabel: '重试',
      retryable: true,
    ),
    UbaaErrorCode.internalError => const UiError(
      code: UbaaErrorCode.internalError,
      title: '应用内部错误',
      message: '请重试；如果问题持续，请反馈错误编号。',
      actionLabel: '重试',
      retryable: true,
    ),
    UbaaErrorCode.unsupported => const UiError(
      code: UbaaErrorCode.unsupported,
      title: '暂不支持',
      message: '当前平台或版本暂不支持此功能。',
    ),
    UbaaErrorCode.confirmationRequired => const UiError(
      code: UbaaErrorCode.confirmationRequired,
      title: '需要确认',
      message: '请先查看并确认本次操作的目标与影响。',
    ),
    UbaaErrorCode.intentExpired => const UiError(
      code: UbaaErrorCode.intentExpired,
      title: '确认已过期',
      message: '操作确认已过期，请重新准备。',
      actionLabel: '重新准备',
    ),
    UbaaErrorCode.operationConflict => const UiError(
      code: UbaaErrorCode.operationConflict,
      title: '操作状态已变化',
      message: '路线或会话已变化，请重新准备操作。',
      actionLabel: '重新准备',
    ),
    UbaaErrorCode.outcomeUnknown => const UiError(
      code: UbaaErrorCode.outcomeUnknown,
      title: '结果待核对',
      message: '操作结果暂时无法确认，请先刷新相关状态，勿重复提交。',
      actionLabel: '刷新状态',
    ),
  };
}

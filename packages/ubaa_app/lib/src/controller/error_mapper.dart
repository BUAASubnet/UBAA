import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

import '../contracts/backend.dart';

/// 兼容应用入口；展示模板和恢复策略只由 platform 的映射器拥有。
class UbaaErrorMapper {
  const UbaaErrorMapper._();

  static UiError fromCode(UbaaErrorCode code) =>
      const UiErrorMapper().fromCore(CoreErrorPayload(code: code.wireName));

  static UiError fromException(BackendException error) =>
      const UiErrorMapper().fromCore(
        CoreErrorPayload(
          code: error.code.wireName,
          kind: error.kind?.name,
          retryable: error.retryable,
          resolvedRoute: error.resolvedRoute,
          issueId: error.issueId,
        ),
      );

  /// 不把异常正文作为用户提示；已验证的 typed 错误保留机器元数据。
  static UiError fromObject(Object error) => switch (error) {
    BackendException value => fromException(value),
    UiError value => fromException(BackendException.fromUi(value)),
    _ => const UiErrorMapper().fromException(error),
  };
}

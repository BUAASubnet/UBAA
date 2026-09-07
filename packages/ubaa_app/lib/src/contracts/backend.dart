import 'package:ubaa_domain/ubaa_domain.dart';

/// Core 当前认证状态的最小表示。
enum AuthStatus { signedOut, signedIn }

/// Bridge/Core 错误的安全边界。`detail` 只能记录脱敏诊断，不得传给 UI。
class BackendException implements Exception {
  const BackendException(
    this.code, {
    this.detail,
    this.kind,
    this.retryable,
    this.resolvedRoute,
    this.issueId,
  });

  /// 跨协调器兼容入口重新抛出时，不再把完整错误压缩成单个代码。
  factory BackendException.fromUi(UiError error) => BackendException(
    error.code,
    kind: error.kind,
    retryable: error.retryable,
    resolvedRoute: error.resolvedRoute,
    issueId: error.issueId,
  );

  final UbaaErrorCode code;
  final String? detail;
  final UbaaErrorKind? kind;
  final bool? retryable;
  final ConnectionMode? resolvedRoute;
  final String? issueId;

  @override
  String toString() => 'BackendException(${code.wireName})';
}

/// Flutter 宿主唯一需要依赖的业务接口。
///
/// 生产实现由 FRB 绑定适配；URL、Cookie、路由探测和会话文件均留在 Rust
/// Core 内部，Dart 层不拼接请求。
abstract interface class UbaaBackend {
  Future<AuthStatus> authStatus();

  Future<UserSummary?> userInfo();

  Future<void> prepareLogin(RoutePolicy policy);

  Future<void> login(LoginInput input);

  Future<void> logout();

  /// 首发只读功能统一返回摘要。详情 DTO 接入时保持此接口的错误语义。
  Future<FeatureResult> loadFeature(FeatureId feature);
}

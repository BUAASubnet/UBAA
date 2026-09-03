import 'package:ubaa_domain/ubaa_domain.dart';

import '../contracts/backend.dart';
import '../contracts/lifecycle.dart';

/// 生产配置暂不可用时的安全后端。
///
/// 生产入口不能使用 [DemoBackend] 伪造登录或业务数据；路径、动态库或
/// 平台能力尚未准备好时，所有操作明确失败并由 UI 映射为可行动错误。
class UnavailableBackend implements UbaaBackend, BackendLifecycle {
  const UnavailableBackend();

  @override
  Future<AuthStatus> authStatus() => _unsupported<AuthStatus>();

  @override
  Future<UserSummary?> userInfo() => _unsupported<UserSummary?>();

  @override
  Future<void> prepareLogin(RoutePolicy policy) => _unsupported<void>();

  @override
  Future<void> login(LoginInput input) => _unsupported<void>();

  @override
  Future<void> logout() => _unsupported<void>();

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) =>
      _unsupported<FeatureResult>();

  @override
  Future<void> dispose() async {}

  Future<T> _unsupported<T>() =>
      Future<T>.error(const BackendException(UbaaErrorCode.unsupported));
}

import 'package:ubaa_domain/ubaa_domain.dart';

/// Core 当前保存的全局路线策略和已认证路线槽位。
///
/// 该投影不包含 Session 内容；调用方只能据此决定是否需要重新登录目标路线。
class BackendRouteSettings {
  const BackendRouteSettings({
    required this.defaultPolicy,
    required this.activeRoutes,
  });

  final RoutePolicy defaultPolicy;
  final List<ConnectionMode> activeRoutes;
}

/// 支持读取全局路线策略和已认证路线槽位的生产 backend 能力。
abstract interface class RouteSettingsBackend {
  Future<BackendRouteSettings> routeSettings();
}

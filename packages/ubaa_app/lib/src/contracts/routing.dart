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

/// 保存路线策略，不读取登录页或重置已认证会话。
abstract interface class RoutePolicyBackend {
  Future<BackendRouteSettings> setDefaultRoutePolicy(RoutePolicy policy);
}

enum BackendNetworkState { campus, offCampus, unknown }

/// 换网观察与读取取消独立于业务锁；句柄绑定原始恢复期限。
abstract interface class NetworkChangeBackend {
  NetworkChangeOperation beginNetworkChange({
    required bool online,
    required Duration budget,
  });
  void cancelNetworkReads();
}

abstract interface class NetworkChangeOperation {
  Future<BackendNetworkState> inspect();
  void finish();
  void cancel();
}

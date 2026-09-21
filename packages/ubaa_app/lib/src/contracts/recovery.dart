import 'package:ubaa_domain/ubaa_domain.dart';

/// 单一路线的已核实身份，不表示另一条路线已经就绪。
final class RecoveredRouteSession {
  const RecoveredRouteSession({required this.route, required this.profile});
  final ConnectionMode route;
  final UserSummary profile;
}

/// 生产所需路线恢复；目标由 Core 解析，密码只向明确失效的目标提交。
abstract interface class RequiredSessionBackend {
  Future<RecoveredRouteSession> recoverRequiredSession(FeatureId feature);
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  );
}

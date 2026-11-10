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

/// 命令与 GUI 共用的恢复目标，覆盖不在底栏菜单中的只读服务。
enum RecoveryTarget {
  bhpan,
  user,
  portal,
  network,
  finance,
  ihome,
  schedule,
  exam,
  grades,
  classroom,
  spoc,
  judge,
  signin,
  libbook,
  bykc,
  cgyy,
  ygdk,
  evaluation,
  connection;

  static RecoveryTarget fromFeature(FeatureId feature) =>
      RecoveryTarget.values.byName(feature.name);
  FeatureId? get feature => switch (this) {
    user ||
    portal ||
    network ||
    finance ||
    ihome ||
    bhpan ||
    connection => null,
    _ => FeatureId.values.byName(name),
  };
}

abstract interface class RequiredTargetSessionBackend
    implements RequiredSessionBackend {
  Future<RecoveredRouteSession> recoverTargetSession(RecoveryTarget target);
}

/// 一轮首页读取内复用已核实身份，不延长持久会话有效期。
abstract interface class HomeRecoveryBatchBackend {
  Future<int> beginHomeRecoveryBatch();
  Future<void> endHomeRecoveryBatch(int batch);
  Future<void> invalidateHomeRecoveryBatch();
}

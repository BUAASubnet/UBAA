import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../contracts/backend.dart';
import '../../contracts/recovery.dart';
import '../../contracts/session_recovery.dart';
import '../support/mapping.dart';

/// 只借用客户端，不拥有 logout 或客户端 dispose 的权限。
final class BridgeRequiredSessionBackend
    implements ControlledRequiredTargetSessionBackend {
  const BridgeRequiredSessionBackend(this.client);
  final BridgeClient client;
  @override
  RequiredRecoveryOperation startRequiredRecovery(
    FeatureId feature,
    Duration limit,
  ) => startTargetRecovery(RecoveryTarget.fromFeature(feature), limit);
  @override
  RequiredRecoveryOperation startTargetRecovery(
    RecoveryTarget target,
    Duration limit,
  ) => _start(
    limit,
    (control) => client.recoverRequiredSessionControlled(
      feature: _target(target),
      control: control,
    ),
  );
  @override
  RequiredRecoveryOperation startRequiredLogin(
    ConnectionMode route,
    LoginInput input,
    Duration limit,
  ) => _start(
    limit,
    (control) => client.loginRequiredRouteControlled(
      route: bridgeToBridgeConnectionMode(route),
      username: input.username.trim(),
      password: input.password,
      control: control,
    ),
  );
  @override
  Future<RecoveredRouteSession> recoverRequiredSession(FeatureId feature) =>
      _finish(startRequiredRecovery(feature, const Duration(minutes: 2)));
  @override
  Future<RecoveredRouteSession> recoverTargetSession(RecoveryTarget target) =>
      _finish(startTargetRecovery(target, const Duration(minutes: 2)));
  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) => _finish(startRequiredLogin(route, input, const Duration(minutes: 2)));
}

Future<RecoveredRouteSession> _finish(
  RequiredRecoveryOperation operation,
) async {
  try {
    return await operation.result;
  } finally {
    operation.dispose();
  }
}

RequiredRecoveryOperation _start(
  Duration limit,
  Future<BridgeRequiredSession> Function(BridgeRequiredRecoveryControl) invoke,
) {
  final control = BridgeRequiredRecoveryControl(
    timeoutMillis: limit.inMilliseconds.clamp(0, 120000),
  );
  final result = () async {
    try {
      final value = await invoke(control);
      final profile = bridgeProfileSummary(
        value.profile,
        allowSchoolIdIdentity: true,
      );
      if (profile == null)
        throw const BackendException(UbaaErrorCode.upstreamChanged);
      return RecoveredRouteSession(
        route: bridgeToConnectionMode(value.route),
        profile: profile,
      );
    } on BridgeError catch (error) {
      throw bridgeMapError(error);
    }
  }();
  return _BridgeOperation(result, control);
}

final class _BridgeOperation implements RequiredRecoveryOperation {
  _BridgeOperation(this.result, this.control);
  @override
  final Future<RecoveredRouteSession> result;
  final BridgeRequiredRecoveryControl control;
  @override
  void cancel() => control.cancel();
  @override
  void dispose() => control.dispose();
}

BridgeRecoveryFeature _target(RecoveryTarget target) => switch (target) {
  RecoveryTarget.bhpan => BridgeRecoveryFeature.bhpan,
  RecoveryTarget.user => BridgeRecoveryFeature.user,
  RecoveryTarget.portal => BridgeRecoveryFeature.portal,
  RecoveryTarget.network => BridgeRecoveryFeature.network,
  RecoveryTarget.finance => BridgeRecoveryFeature.finance,
  RecoveryTarget.ihome => BridgeRecoveryFeature.ihome,
  RecoveryTarget.schedule => BridgeRecoveryFeature.schedule,
  RecoveryTarget.exam => BridgeRecoveryFeature.exam,
  RecoveryTarget.grades => BridgeRecoveryFeature.grades,
  RecoveryTarget.classroom => BridgeRecoveryFeature.classroom,
  RecoveryTarget.spoc => BridgeRecoveryFeature.spoc,
  RecoveryTarget.judge => BridgeRecoveryFeature.judge,
  RecoveryTarget.signin => BridgeRecoveryFeature.signin,
  RecoveryTarget.libbook => BridgeRecoveryFeature.libBook,
  RecoveryTarget.bykc => BridgeRecoveryFeature.bykc,
  RecoveryTarget.cgyy => BridgeRecoveryFeature.cgyy,
  RecoveryTarget.ygdk => BridgeRecoveryFeature.ygdk,
  RecoveryTarget.evaluation => BridgeRecoveryFeature.evaluation,
};

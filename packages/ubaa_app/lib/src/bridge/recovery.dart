part of 'bridge_backend.dart';

Future<RecoveredRouteSession> _recoverRequiredSession(
  BridgeBackend backend,
  FeatureId feature,
) async {
  try {
    return _recoveredSession(
      await backend.client.recoverRequiredSession(
        feature: _recoveryFeature(feature),
      ),
    );
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

Future<RecoveredRouteSession> _loginRequiredRoute(
  BridgeBackend backend,
  ConnectionMode route,
  LoginInput input,
) async {
  try {
    return _recoveredSession(
      await backend.client.loginRequiredRoute(
        route: _toBridgeConnectionMode(route),
        username: input.username.trim(),
        password: input.password,
      ),
    );
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

RecoveredRouteSession _recoveredSession(BridgeRequiredSession session) {
  final profile = _profileSummary(session.profile, allowSchoolIdIdentity: true);
  if (profile == null)
    throw const BackendException(UbaaErrorCode.upstreamChanged);
  return RecoveredRouteSession(
    route: _toConnectionMode(session.route),
    profile: profile,
  );
}

BridgeRecoveryFeature _recoveryFeature(FeatureId feature) => switch (feature) {
  FeatureId.schedule => BridgeRecoveryFeature.schedule,
  FeatureId.exam => BridgeRecoveryFeature.exam,
  FeatureId.grades => BridgeRecoveryFeature.grades,
  FeatureId.classroom => BridgeRecoveryFeature.classroom,
  FeatureId.spoc => BridgeRecoveryFeature.spoc,
  FeatureId.judge => BridgeRecoveryFeature.judge,
  FeatureId.signin => BridgeRecoveryFeature.signin,
  FeatureId.bykc => BridgeRecoveryFeature.bykc,
  FeatureId.libbook => BridgeRecoveryFeature.libBook,
  FeatureId.cgyy => BridgeRecoveryFeature.cgyy,
  FeatureId.ygdk => BridgeRecoveryFeature.ygdk,
  FeatureId.evaluation => BridgeRecoveryFeature.evaluation,
};

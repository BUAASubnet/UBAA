part of 'session.dart';

Future<RecoveredRouteSession> bridgeRecoverRequiredSession(
  BridgeContext backend,
  FeatureId feature,
) async {
  try {
    return _recoveredSession(
      await backend.client.recoverRequiredSession(
        feature: _recoveryFeature(feature),
      ),
    );
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<RecoveredRouteSession> bridgeLoginRequiredRoute(
  BridgeContext backend,
  ConnectionMode route,
  LoginInput input,
) async {
  try {
    return _recoveredSession(
      await backend.client.loginRequiredRoute(
        route: bridgeToBridgeConnectionMode(route),
        username: input.username.trim(),
        password: input.password,
      ),
    );
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

RecoveredRouteSession _recoveredSession(BridgeRequiredSession session) {
  final profile = bridgeProfileSummary(
    session.profile,
    allowSchoolIdIdentity: true,
  );
  if (profile == null)
    throw const BackendException(UbaaErrorCode.upstreamChanged);
  return RecoveredRouteSession(
    route: bridgeToConnectionMode(session.route),
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

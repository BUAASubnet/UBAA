part of 'session.dart';

Future<RecoveredRouteSession> bridgeRecoverRequiredSession(
  BridgeContext backend,
  FeatureId feature,
) => BridgeRequiredSessionBackend(
  backend.client,
).recoverRequiredSession(feature);

Future<RecoveredRouteSession> bridgeLoginRequiredRoute(
  BridgeContext backend,
  ConnectionMode route,
  LoginInput input,
) => BridgeRequiredSessionBackend(
  backend.client,
).loginRequiredRoute(route, input);

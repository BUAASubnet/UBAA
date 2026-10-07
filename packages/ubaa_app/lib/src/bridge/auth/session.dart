import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../support/mapping.dart'
    show
        bridgeErrorCode,
        bridgeMapError,
        bridgeNonBlank,
        bridgeProfileSummary,
        bridgeSafeErrorKind,
        bridgeToBridgeConnectionMode,
        bridgeToBridgePolicy,
        bridgeToConnectionMode,
        bridgeToRoutePolicy;
part 'recovery.dart';
part 'interactive.dart';

Future<AuthStatus> bridgeAuthStatus(BridgeContext backend) async {
  _interruptInteractiveLogin(backend);
  try {
    final outcome = await backend.client.authStatus();
    if (outcome.readiness != BridgeLoginReadiness.noneReady)
      return AuthStatus.signedIn;
    for (final route in outcome.routes) {
      final failed = route.error;
      if (failed == null)
        throw const BackendException(UbaaErrorCode.internalError);
      if (failed.code != 'authentication_required') {
        throw BackendException(
          bridgeErrorCode(failed.code),
          kind: bridgeSafeErrorKind(failed.kind),
          retryable: failed.retryable,
          resolvedRoute: bridgeToConnectionMode(route.route),
        );
      }
    }
    if (outcome.routes.length != 2)
      throw const BackendException(UbaaErrorCode.internalError);
    return AuthStatus.signedOut;
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<UserSummary?> bridgeUserInfo(BridgeContext backend) async {
  try {
    final result = await backend.client.userInfo();
    return bridgeProfileSummary(result.data);
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<void> bridgePrepareLogin(
  BridgeContext backend,
  RoutePolicy policy,
  Future<BackendRouteSettings> Function(RoutePolicy) setPolicy,
) async {
  _interruptInteractiveLogin(backend);
  try {
    await setPolicy(policy);
    await backend.client.prepareLogin();
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<BackendRouteSettings> bridgeSetDefaultRoutePolicy(
  BridgeContext backend,
  RoutePolicy policy,
) async {
  _interruptInteractiveLogin(backend);
  try {
    final settings = await backend.client.setDefaultRoutePolicy(
      policy: bridgeToBridgePolicy(policy),
    );
    return BackendRouteSettings(
      defaultPolicy: bridgeToRoutePolicy(settings.defaultPolicy),
      activeRoutes: List<ConnectionMode>.unmodifiable(
        settings.activeRoutes.map(bridgeToConnectionMode),
      ),
    );
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<BackendRouteSettings> bridgeRouteSettings(BridgeContext backend) async {
  try {
    final settings = await backend.client.routeSettings();
    return BackendRouteSettings(
      defaultPolicy: bridgeToRoutePolicy(settings.defaultPolicy),
      activeRoutes: List<ConnectionMode>.unmodifiable(
        settings.activeRoutes.map(bridgeToConnectionMode),
      ),
    );
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<void> bridgeLogin(BridgeContext backend, LoginInput input) async {
  _interruptInteractiveLogin(backend);
  try {
    await backend.client.setDefaultRoutePolicy(
      policy: bridgeToBridgePolicy(input.routePolicy),
    );
    final outcome = await backend.client.login(
      username: input.username.trim(),
      password: input.password,
    );
    if (outcome.readiness == BridgeLoginReadiness.noneReady) {
      for (final route in outcome.routes) {
        final failed = route.error;
        if (failed != null) {
          throw BackendException(
            bridgeErrorCode(failed.code),
            kind: bridgeSafeErrorKind(failed.kind),
            retryable: failed.retryable,
            resolvedRoute: bridgeToConnectionMode(route.route),
          );
        }
      }
      throw const BackendException(UbaaErrorCode.internalError);
    }
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<void> bridgeLogout(BridgeContext backend) async {
  _interruptInteractiveLogin(backend);
  try {
    await backend.client.logout();
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<void> bridgeDispose(BridgeContext backend) {
  _interruptInteractiveLogin(backend);
  return backend.client.dispose();
}

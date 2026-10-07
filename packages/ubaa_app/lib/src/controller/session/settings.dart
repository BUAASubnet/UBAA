import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/routing.dart';
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase;

mixin ControllerSettings on ControllerState {
  @internal
  Future<void> internalSetRoutePolicyController(RoutePolicy value) async {
    if (internalDisposed || isLoggingIn || internalIsSigningOut) return;
    final previousPolicy = internalLoginForm.routePolicy;
    if (previousPolicy == value && !internalRoutePolicyInFlight) return;
    internalCancelLoginVerification(releasePassword: false, notify: false);
    final backend = internalBackend;
    final credentials = internalLoginCredentialRevision;
    final request = ++internalRoutePolicyGeneration;
    internalRoutePolicyInFlight = true;
    internalBeginWriteTransition();
    final epoch = internalLifecycleEpoch;
    bool isCurrent() =>
        !internalDisposed &&
        !internalIsSigningOut &&
        identical(backend, internalBackend) &&
        epoch == internalLifecycleEpoch &&
        credentials == internalLoginCredentialRevision &&
        request == internalRoutePolicyGeneration;
    internalClearError();
    try {
      await backend.prepareLogin(value);
      if (!isCurrent()) return;
      BackendRouteSettings? settings;
      if (backend case final RouteSettingsBackend routeBackend) {
        settings = await routeBackend.routeSettings();
        if (!isCurrent()) return;
      }
      if (settings case final routeSettings?) {
        internalApplyRouteSettings(routeSettings);
      } else {
        internalLoginForm = internalLoginForm.copyWith(routePolicy: value);
      }
      if (internalPhase == AppPhase.home &&
          settings != null &&
          !internalRoutePolicyHasSession(value, settings.activeRoutes)) {
        // 切换到尚未认证的固定路线时，不能继续展示旧用户数据；保留用户名和
        // 用户主动保存的凭据，回到登录页完成目标路线认证。
        internalUser = null;
        internalResetFeatureSnapshots();
        internalSetPhase(AppPhase.login);
      }
    } on BackendException catch (exception, stackTrace) {
      if (!isCurrent()) return;
      internalLoginForm = internalLoginForm.copyWith(
        routePolicy: previousPolicy,
      );
      internalError = internalRecordFailure(
        exception,
        DiagnosticOperation.routeChange,
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      if (!isCurrent()) return;
      internalLoginForm = internalLoginForm.copyWith(
        routePolicy: previousPolicy,
      );
      internalError = internalRecordFailure(
        error,
        DiagnosticOperation.routeChange,
        stackTrace: stackTrace,
      );
    } finally {
      if (request == internalRoutePolicyGeneration)
        internalRoutePolicyInFlight = false;
      internalEndWriteTransition();
    }
    internalNotify();
    unawaited(internalQueueProfileRefresh(force: true));
  }

  @internal
  Future<void> internalSetTelemetryEnabledController(bool value) async {
    // Noop不能把本地布尔值当作统计已开启；可用客户端仍在调用边界开关。
    internalTelemetryEnabled = value && telemetryAvailable;
    if (!value) await internalFlushTelemetry();
    internalNotify();
  }
}

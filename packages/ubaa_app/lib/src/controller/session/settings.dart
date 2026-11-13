import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/routing.dart';
import '../state/activity.dart';
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
    final queries = {
      for (final entry in internalSnapshots.entries)
        if (entry.value.readContext?.query case final query?) entry.key: query,
    };
    final credentials = internalLoginCredentialRevision;
    final request = ++internalRoutePolicyGeneration;
    internalRoutePolicyReadRevision = internalReadRequestRevision;
    internalRoutePolicyInFlight = true;
    final activity = internalBeginOperationTransition(
      ControllerActivityKind.routeChange,
    );
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
      BackendRouteSettings? settings;
      if (backend case final RoutePolicyBackend routeBackend) {
        if (backend case final NetworkChangeBackend networkBackend)
          networkBackend.cancelNetworkReads();
        settings = await routeBackend.setDefaultRoutePolicy(value);
        if (!isCurrent()) return;
      } else {
        await backend.prepareLogin(value);
        if (!isCurrent()) return;
        if (backend case final RouteSettingsBackend routeBackend) {
          settings = await routeBackend.routeSettings();
          if (!isCurrent()) return;
        }
      }
      if (settings case final routeSettings?) {
        internalApplyRouteSettings(routeSettings);
      } else {
        internalLoginForm = internalLoginForm.copyWith(routePolicy: value);
      }
      if (internalPhase == AppPhase.home &&
          backend is! RoutePolicyBackend &&
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
      internalEndOperationTransition(activity);
      // 旧请求也可能是最后一个 transition；收尾必须通知首页恢复纯投影。
      internalNotify();
    }
    if (isCurrent() &&
        internalError == null &&
        backend is RoutePolicyBackend &&
        internalPhase == AppPhase.home) {
      internalHandleNetworkChange(online: internalNetworkOnline);
      await internalNetworkReady?.future;
      if (!isCurrent() || internalNetworkFailure != null) return;
      for (final entry in queries.entries) {
        if (internalSnapshots[entry.key]!.readContext?.hasSameQuery(
              entry.value,
            ) ??
            false) {
          unawaited(
            internalAutomaticSchoolAction(
              () => internalRefreshFeatureQuery(entry.key, entry.value),
            ),
          );
        }
      }
    }
    unawaited(
      internalAutomaticSchoolAction(
        () => internalQueueProfileRefresh(force: true),
      ),
    );
  }
}

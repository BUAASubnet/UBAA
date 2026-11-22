import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/interactive_auth.dart';
import '../lifecycle/app_service.dart' show ControllerAppService;
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase;

mixin ControllerFormActions on ControllerState, ControllerAppService {
  void setCaptchaAnswer(ConnectionMode route, String answer) =>
      internalSetCaptchaAnswer(route, answer);

  Future<void> refreshCaptcha(ConnectionMode route) =>
      internalUserSchoolAction(() => internalRefreshCaptcha(route));

  Future<void> continueReadyLogin(ConnectionMode route) =>
      internalUserSchoolAction(() => internalContinueReadyLogin(route));

  Future<void> continueWithFixedReadyRoute(ConnectionMode route) =>
      internalUserSchoolAction(
        () => internalContinueReadyLogin(route, pinRoute: true),
      );

  void cancelLoginVerification() => internalCancelLoginVerification();

  void setUsername(String value) {
    if (internalDisposed || isLoggingIn || internalIsSigningOut) return;
    final accountChanged = value.trim() != internalLoginForm.username.trim();
    if (accountChanged)
      internalCancelLoginVerification(releasePassword: false, notify: false);
    if (accountChanged) internalManualAuthenticationRequired = true;
    internalLoginFormRevision++;
    internalLoginCredentialRevision++;
    internalLoginForm = internalLoginForm.copyWith(
      username: value,
      password: accountChanged ? '' : null,
      captcha: accountChanged ? '' : null,
    );
    internalError = null;
    internalNotify();
  }

  void setPassword(String value) {
    if (internalDisposed || isLoggingIn || internalIsSigningOut) return;
    if (value != internalLoginForm.password)
      internalCancelLoginVerification(releasePassword: false, notify: false);
    internalLoginFormRevision++;
    internalLoginCredentialRevision++;
    internalLoginForm = internalLoginForm.copyWith(password: value);
    internalError = null;
    internalNotify();
  }

  void setCaptcha(String value) {
    if (internalDisposed || isLoggingIn || internalIsSigningOut) return;
    internalLoginFormRevision++;
    internalLoginCredentialRevision++;
    internalLoginForm = internalLoginForm.copyWith(captcha: value);
    internalError = null;
    internalNotify();
  }

  void setRememberPassword(bool value) {
    if (!internalCanEditLoginOptions) return;
    internalLoginCredentialRevision++;
    if (!value) internalAutomaticLoginDisabled = true;
    internalLoginFormRevision++;
    internalLoginForm = internalLoginForm.copyWith(
      rememberPassword: value,
      autoLogin: value ? internalLoginForm.autoLogin : false,
    );
    internalNotify();
  }

  void setAutoLogin(bool value) {
    if (!internalCanEditLoginOptions) return;
    internalLoginCredentialRevision++;
    internalAutomaticLoginDisabled = !value;
    internalLoginFormRevision++;
    internalLoginForm = internalLoginForm.copyWith(
      autoLogin: value,
      rememberPassword: value ? true : internalLoginForm.rememberPassword,
    );
    internalNotify();
  }

  Future<void> setRoutePolicy(RoutePolicy value) =>
      internalUserSchoolAction(() => internalSetRoutePolicyController(value));

  Future<void> submitLogin({bool preserveHome = false}) =>
      !internalPrivacyAccepted
      ? Future.value()
      : internalUserSchoolAction(() async {
          if (internalDisposed) return;
          if (internalAppServiceView.consent == AppServiceConsent.agreed &&
              internalAppServiceView.update?.gateActive == true) {
            final view = await internalReadAppService();
            if (internalDisposed) return;
            if (view != null &&
                view.consent == AppServiceConsent.agreed &&
                view.update?.gateActive == true) {
              internalError = internalRecordFailure(
                const BackendException(
                  UbaaErrorCode.updateRequired,
                  retryable: false,
                ),
                DiagnosticOperation.login,
              );
              internalNotify();
              return;
            }
          }
          if (internalBackendNeedsRebuild) {
            final rebuilding = internalBackendRebuildCompletion;
            if (rebuilding != null) {
              await rebuilding.future;
            } else if (!await rebuildBackend()) {
              if (!internalDisposed &&
                  !internalIsSigningOut &&
                  internalError == null) {
                internalError = internalRecordFailure(
                  const BackendException(
                    UbaaErrorCode.internalError,
                    clientDisposed: true,
                  ),
                  DiagnosticOperation.login,
                );
                internalNotify();
              }
              return;
            }
            if (internalDisposed ||
                internalIsSigningOut ||
                internalBackendNeedsRebuild)
              return;
          }
          if (internalBackend case final InteractiveLoginBackend backend) {
            if (internalDisposed ||
                internalIsSigningOut ||
                internalRebuildingBackend ||
                internalSessionRecoveryFuture != null ||
                internalWriteCoordinator.hasPendingOperation ||
                internalActivities.hasActive)
              return Future.value();
            if (!internalInteractiveEngaged)
              internalInteractiveInPlace =
                  preserveHome && internalPhase == AppPhase.home;
            return internalSubmitInteractiveLogin(backend);
          }
          return internalSubmitLoginController(preserveHome: preserveHome);
        });
}

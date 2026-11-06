part of 'ubaa_app_host.dart';

extension _UbaaAppHostSession on _UbaaAppHostState {
  Widget _buildLoginView({
    bool inPlace = false,
    VoidCallback? onAuthenticated,
  }) => UbaaLoginView(
    username: _controller.loginForm.username,
    password: _controller.loginForm.password,
    captcha: _controller.loginForm.captcha,
    verification: _controller.loginVerification,
    rememberPassword: _controller.loginForm.rememberPassword,
    autoLogin: _controller.loginForm.autoLogin,
    routePolicy: _controller.loginForm.routePolicy,
    error: _controller.error,
    onOpenAppLink: (widget.appInformation ?? SystemAppInformation()).open,
    onReadDiagnostics: _controller.exportDiagnostics,
    isLoading: _controller.isLoggingIn,
    credentialPersistenceAvailable: _controller.credentialPersistenceAvailable,
    onUsernameChanged: _controller.setUsername,
    onPasswordChanged: _controller.setPassword,
    onCaptchaChanged: _controller.setCaptcha,
    onRememberPasswordChanged: _controller.setRememberPassword,
    onAutoLoginChanged: _controller.setAutoLogin,
    onSubmit: () => unawaited(() async {
      await _controller.submitLogin(preserveHome: inPlace);
      if (!_disposed &&
          _controller.sessionRecoveryStatus == SessionRecoveryStatus.ready) {
        onAuthenticated?.call();
      }
    }()),
  );

  void _showInPlaceLogin(BuildContext context) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) {
          _loginSheetRoute = ModalRoute.of(sheetContext);
          return FractionallySizedBox(
            heightFactor: 0.95,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, _) => _buildLoginView(
                inPlace: true,
                onAuthenticated: () {
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
            ),
          );
        },
      ).whenComplete(() {
        _loginSheetRoute = null;
        _controller.cancelLoginVerification();
      }),
    );
  }

  void _syncCaptchaDialog() {
    if (_disposed || _readyController == null) return;
    final state = _controller.loginVerification;
    if (_wasBackgrounded || state == null || !state.hasCaptcha) {
      final route = _captchaDialogRoute;
      if (route != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (route.isActive) route.navigator?.removeRoute(route);
        });
      }
      return;
    }
    if (_controller.isLoggingIn ||
        _captchaDialogRoute != null ||
        _captchaDialogScheduled)
      return;
    _captchaDialogScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captchaDialogScheduled = false;
      if (_disposed ||
          _wasBackgrounded ||
          _controller.isLoggingIn ||
          !(_controller.loginVerification?.hasCaptcha ?? false) ||
          _captchaDialogRoute != null)
        return;
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;
      final route = DialogRoute<void>(
        context: navigator.context,
        builder: (_) => AnimatedBuilder(
          animation: _controller,
          builder: (_, _) {
            final state = _controller.loginVerification;
            final pending = state?.routes
                .where(
                  (item) =>
                      item.status ==
                      LoginRouteVerificationStatus.captchaRequired,
                )
                .firstOrNull;
            if (pending == null) return const SizedBox.shrink();
            return UbaaCaptchaDialog(
              verification: pending,
              isLoading: _controller.isLoggingIn,
              onAnswerChanged: (answer) =>
                  _controller.setCaptchaAnswer(pending.route, answer),
              onRefresh: () =>
                  unawaited(_controller.refreshCaptcha(pending.route)),
              onCancel: _controller.cancelLoginVerification,
              onSubmit: () => unawaited(_submitCaptcha()),
            );
          },
        ),
      );
      _captchaDialogRoute = route;
      unawaited(
        navigator.push(route).whenComplete(() {
          if (identical(_captchaDialogRoute, route)) _captchaDialogRoute = null;
          if (!_disposed &&
              (_controller.loginVerification?.hasCaptcha ?? false)) {
            _controller.cancelLoginVerification();
          }
        }),
      );
    });
  }

  Future<void> _submitCaptcha() async {
    await _controller.submitLogin(preserveHome: true);
    if (_disposed ||
        _controller.sessionRecoveryStatus != SessionRecoveryStatus.ready)
      return;
    final sheet = _loginSheetRoute;
    if (sheet != null && sheet.isActive) sheet.navigator?.removeRoute(sheet);
  }
}

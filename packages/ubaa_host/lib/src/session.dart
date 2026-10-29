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
    onCaptchaAnswerChanged: _controller.setCaptchaAnswer,
    onRefreshCaptcha: (route) => unawaited(_controller.refreshCaptcha(route)),
    onContinueReady: (route) => unawaited(
      _completeLoginInteraction(
        _controller.continueReadyLogin(route),
        onAuthenticated,
      ),
    ),
    onContinueFixedReady: (route) => unawaited(
      _completeLoginInteraction(
        _controller.continueWithFixedReadyRoute(route),
        onAuthenticated,
      ),
    ),
    onCancelVerification: _controller.cancelLoginVerification,
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

  Future<void> _completeLoginInteraction(
    Future<void> task,
    VoidCallback? onAuthenticated,
  ) async {
    await task;
    if (!_disposed &&
        _controller.sessionRecoveryStatus == SessionRecoveryStatus.ready)
      onAuthenticated?.call();
  }

  void _showInPlaceLogin(BuildContext context) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => FractionallySizedBox(
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
        ),
      ).whenComplete(_controller.cancelLoginVerification),
    );
  }
}

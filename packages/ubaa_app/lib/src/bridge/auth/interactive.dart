part of 'session.dart';

Future<LoginVerificationState> bridgeBeginInteractiveLogin(
  BridgeContext backend,
  LoginInput input,
) async {
  bridgeCancelInteractiveLogin(backend);
  final generation = backend.authentication.generation;
  try {
    // 只有新手动登录可走旧策略重开入口；当前交互的刷新与继续绝不走这里。
    await backend.client.setDefaultRoutePolicy(
      policy: bridgeToBridgePolicy(input.routePolicy),
    );
    _checkInteractiveGeneration(backend, generation);
    final login = backend.client.beginInteractiveLogin(
      username: input.username.trim(),
    );
    backend.authentication.login = login;
    final prepared = await backend.client.prepareInteractiveLogin(login: login);
    _checkInteractiveGeneration(backend, generation);
    var state = _acceptInteractiveOutcome(backend, prepared);
    if (state.routes.any(
      (route) => route.status == LoginRouteVerificationStatus.prepared,
    )) {
      final submitted = await backend.client.submitInteractiveLogin(
        login: login,
        username: input.username.trim(),
        password: input.password,
        answers: const <BridgeCaptchaAnswer>[],
      );
      _checkInteractiveGeneration(backend, generation);
      state = _acceptInteractiveOutcome(backend, submitted);
    }
    return state;
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<LoginVerificationState> bridgeSubmitInteractiveLogin(
  BridgeContext backend,
  LoginInput input,
  Map<ConnectionMode, String> answers,
) async {
  final generation = backend.authentication.generation;
  final login = backend.authentication.login;
  if (login == null) throw const BackendException(UbaaErrorCode.invalidInput);
  final values = <BridgeCaptchaAnswer>[];
  for (final entry in answers.entries) {
    final challenge = backend.authentication.challenges[entry.key];
    if (challenge == null)
      throw const BackendException(UbaaErrorCode.invalidInput);
    if (entry.value.trim().isNotEmpty) {
      values.add(
        BridgeCaptchaAnswer(challenge: challenge, answer: entry.value),
      );
    }
  }
  try {
    final result = await backend.client.submitInteractiveLogin(
      login: login,
      username: input.username.trim(),
      password: input.password,
      answers: values,
    );
    _checkInteractiveGeneration(backend, generation);
    return _acceptInteractiveOutcome(backend, result);
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<LoginVerificationState> bridgeRefreshInteractiveCaptcha(
  BridgeContext backend,
  ConnectionMode route,
) async {
  final generation = backend.authentication.generation;
  final login = backend.authentication.login;
  if (login == null) throw const BackendException(UbaaErrorCode.invalidInput);
  bridgeDiscardInteractiveCaptcha(backend, route);
  try {
    final result = await backend.client.refreshInteractiveCaptcha(
      login: login,
      route: bridgeToBridgeConnectionMode(route),
    );
    _checkInteractiveGeneration(backend, generation);
    return _acceptInteractiveOutcome(backend, result);
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

Future<InteractiveLoginCompletion> bridgeContinueInteractiveLogin(
  BridgeContext backend,
  ConnectionMode route, {
  bool pinRoute = false,
}) async {
  final generation = backend.authentication.generation;
  final login = backend.authentication.login;
  if (login == null) throw const BackendException(UbaaErrorCode.invalidInput);
  try {
    final completed = await backend.client.continueInteractiveLogin(
      login: login,
      selectedRoute: bridgeToBridgeConnectionMode(route),
      pinReadyRoute: pinRoute,
    );
    _checkInteractiveGeneration(backend, generation);
    final profile = completed.outcome.profile;
    if (profile == null)
      throw const BackendException(UbaaErrorCode.upstreamChanged);
    final result = InteractiveLoginCompletion(
      user: _interactiveProfile(profile),
      settings: BackendRouteSettings(
        defaultPolicy: bridgeToRoutePolicy(completed.settings.defaultPolicy),
        activeRoutes: List<ConnectionMode>.unmodifiable(
          completed.settings.activeRoutes.map(bridgeToConnectionMode),
        ),
      ),
    );
    _releaseInteractiveReferences(backend);
    return result;
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}

LoginVerificationState _acceptInteractiveOutcome(
  BridgeContext backend,
  BridgeInteractiveLoginOutcome outcome,
) {
  final previous = backend.authentication.state;
  final routes = <LoginRouteVerification>[];
  for (final value in outcome.routes) {
    final route = bridgeToConnectionMode(value.route);
    final revision = value.revision.toInt();
    final old = previous?.forRoute(route);
    final status = switch (value.state) {
      BridgeInteractiveRouteState.prepared =>
        LoginRouteVerificationStatus.prepared,
      BridgeInteractiveRouteState.captchaRequired =>
        LoginRouteVerificationStatus.captchaRequired,
      BridgeInteractiveRouteState.ready => LoginRouteVerificationStatus.ready,
      BridgeInteractiveRouteState.failed => LoginRouteVerificationStatus.failed,
    };
    final same =
        old?.revision == revision &&
        status == LoginRouteVerificationStatus.captchaRequired;
    CaptchaPixelFrame? frame;
    if (value.frame case final incoming?) {
      if (incoming.width < 1 ||
          incoming.height < 1 ||
          incoming.width > 1024 ||
          incoming.height > 1024 ||
          incoming.rgba.length != incoming.width * incoming.height * 4 ||
          value.challenge == null ||
          value.validForMillis <= 0 ||
          value.validForMillis > 120000) {
        throw const BackendException(UbaaErrorCode.upstreamChanged);
      }
      frame = CaptchaPixelFrame(
        width: incoming.width,
        height: incoming.height,
        rgba: incoming.rgba,
      );
    } else if (same && value.challenge != null) {
      frame = old?.frame;
    }
    if (!identical(old?.frame, frame)) old?.frame?.release();
    if (value.challenge case final challenge?) {
      backend.authentication.challenges[route] = challenge;
    } else {
      backend.authentication.challenges.remove(route)?.cancel();
    }
    final error = value.error;
    routes.add(
      LoginRouteVerification(
        route: route,
        status: status,
        revision: revision,
        frame: frame,
        validFor: Duration(milliseconds: value.validForMillis),
        error: error == null
            ? null
            : const UiErrorMapper().fromCore(
                CoreErrorPayload(
                  code: error.code,
                  kind: error.kind,
                  retryable: error.retryable,
                  resolvedRoute: route,
                ),
              ),
      ),
    );
  }
  final state = LoginVerificationState(
    routes: routes,
    profile: outcome.profile == null
        ? null
        : _interactiveProfile(outcome.profile!),
  );
  backend.authentication.login = outcome.login;
  backend.authentication.state = state;
  return state;
}

UserSummary _interactiveProfile(BridgeUserProfile profile) => UserSummary(
  username:
      bridgeNonBlank(profile.username) ??
      bridgeNonBlank(profile.schoolId) ??
      '',
  displayName: bridgeNonBlank(profile.name),
  schoolId: bridgeNonBlank(profile.schoolId),
  email: bridgeNonBlank(profile.email),
  phone: bridgeNonBlank(profile.phone),
  idCardTypeName: bridgeNonBlank(profile.idCardTypeName),
);

void _checkInteractiveGeneration(BridgeContext backend, int generation) {
  if (backend.authentication.generation != generation) {
    throw const BackendException(UbaaErrorCode.invalidInput);
  }
}

void bridgeDiscardInteractiveCaptcha(
  BridgeContext backend,
  ConnectionMode route,
) {
  backend.authentication.challenges.remove(route)?.cancel();
  final previous = backend.authentication.state;
  if (previous == null) return;
  previous.forRoute(route)?.frame?.release();
  backend.authentication.state = LoginVerificationState(
    profile: previous.profile,
    routes: <LoginRouteVerification>[
      for (final value in previous.routes)
        value.route == route ? value.cleared() : value,
    ],
  );
}

void _releaseInteractiveReferences(BridgeContext backend) {
  backend.authentication.state?.releaseFrames();
  backend.authentication.state = null;
  backend.authentication.login = null;
  backend.authentication.challenges.clear();
}

void bridgeCancelInteractiveLogin(BridgeContext backend) {
  backend.authentication.generation++;
  _releaseInteractiveReferences(backend);
  backend.client.cancelInteractiveLogin();
}

void _interruptInteractiveLogin(BridgeContext backend) {
  final hadHandle = backend.authentication.login != null;
  backend.authentication.generation++;
  _releaseInteractiveReferences(backend);
  if (hadHandle) backend.client.cancelInteractiveLogin();
}

part of 'bridge_backend.dart';

Future<LoginVerificationState> _beginInteractiveLogin(
  BridgeBackend backend,
  LoginInput input,
) async {
  _cancelInteractiveLogin(backend);
  final generation = backend._interactiveGeneration;
  try {
    // 只有新手动登录可走旧策略重开入口；当前交互的刷新与继续绝不走这里。
    await backend.client.setDefaultRoutePolicy(
      policy: _toBridgePolicy(input.routePolicy),
    );
    _checkInteractiveGeneration(backend, generation);
    final login = backend.client.beginInteractiveLogin(
      username: input.username.trim(),
    );
    backend._interactiveLogin = login;
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
    throw _mapError(error);
  }
}

Future<LoginVerificationState> _submitInteractiveLogin(
  BridgeBackend backend,
  LoginInput input,
  Map<ConnectionMode, String> answers,
) async {
  final generation = backend._interactiveGeneration;
  final login = backend._interactiveLogin;
  if (login == null) throw const BackendException(UbaaErrorCode.invalidInput);
  final values = <BridgeCaptchaAnswer>[];
  for (final entry in answers.entries) {
    final challenge = backend._interactiveChallenges[entry.key];
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
    throw _mapError(error);
  }
}

Future<LoginVerificationState> _refreshInteractiveCaptcha(
  BridgeBackend backend,
  ConnectionMode route,
) async {
  final generation = backend._interactiveGeneration;
  final login = backend._interactiveLogin;
  if (login == null) throw const BackendException(UbaaErrorCode.invalidInput);
  _discardInteractiveCaptcha(backend, route);
  try {
    final result = await backend.client.refreshInteractiveCaptcha(
      login: login,
      route: _toBridgeConnectionMode(route),
    );
    _checkInteractiveGeneration(backend, generation);
    return _acceptInteractiveOutcome(backend, result);
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

Future<InteractiveLoginCompletion> _continueInteractiveLogin(
  BridgeBackend backend,
  ConnectionMode route, {
  bool pinRoute = false,
}) async {
  final generation = backend._interactiveGeneration;
  final login = backend._interactiveLogin;
  if (login == null) throw const BackendException(UbaaErrorCode.invalidInput);
  try {
    final completed = await backend.client.continueInteractiveLogin(
      login: login,
      selectedRoute: _toBridgeConnectionMode(route),
      pinReadyRoute: pinRoute,
    );
    _checkInteractiveGeneration(backend, generation);
    final profile = completed.outcome.profile;
    if (profile == null)
      throw const BackendException(UbaaErrorCode.upstreamChanged);
    final result = InteractiveLoginCompletion(
      user: _interactiveProfile(profile),
      settings: BackendRouteSettings(
        defaultPolicy: _toRoutePolicy(completed.settings.defaultPolicy),
        activeRoutes: List<ConnectionMode>.unmodifiable(
          completed.settings.activeRoutes.map(_toConnectionMode),
        ),
      ),
    );
    _releaseInteractiveReferences(backend);
    return result;
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

LoginVerificationState _acceptInteractiveOutcome(
  BridgeBackend backend,
  BridgeInteractiveLoginOutcome outcome,
) {
  final previous = backend._interactiveState;
  final routes = <LoginRouteVerification>[];
  for (final value in outcome.routes) {
    final route = _toConnectionMode(value.route);
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
      backend._interactiveChallenges[route] = challenge;
    } else {
      backend._interactiveChallenges.remove(route)?.cancel();
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
  backend._interactiveLogin = outcome.login;
  backend._interactiveState = state;
  return state;
}

UserSummary _interactiveProfile(BridgeUserProfile profile) => UserSummary(
  username: _nonBlank(profile.username) ?? _nonBlank(profile.schoolId) ?? '',
  displayName: _nonBlank(profile.name),
  schoolId: _nonBlank(profile.schoolId),
  email: _nonBlank(profile.email),
  phone: _nonBlank(profile.phone),
  idCardTypeName: _nonBlank(profile.idCardTypeName),
);

void _checkInteractiveGeneration(BridgeBackend backend, int generation) {
  if (backend._interactiveGeneration != generation) {
    throw const BackendException(UbaaErrorCode.invalidInput);
  }
}

void _discardInteractiveCaptcha(BridgeBackend backend, ConnectionMode route) {
  backend._interactiveChallenges.remove(route)?.cancel();
  final previous = backend._interactiveState;
  if (previous == null) return;
  previous.forRoute(route)?.frame?.release();
  backend._interactiveState = LoginVerificationState(
    profile: previous.profile,
    routes: <LoginRouteVerification>[
      for (final value in previous.routes)
        value.route == route ? value.cleared() : value,
    ],
  );
}

void _releaseInteractiveReferences(BridgeBackend backend) {
  backend._interactiveState?.releaseFrames();
  backend._interactiveState = null;
  backend._interactiveLogin = null;
  backend._interactiveChallenges.clear();
}

void _cancelInteractiveLogin(BridgeBackend backend) {
  backend._interactiveGeneration++;
  _releaseInteractiveReferences(backend);
  backend.client.cancelInteractiveLogin();
}

void _interruptInteractiveLogin(BridgeBackend backend) {
  final hadHandle = backend._interactiveLogin != null;
  backend._interactiveGeneration++;
  _releaseInteractiveReferences(backend);
  if (hadHandle) backend.client.cancelInteractiveLogin();
}

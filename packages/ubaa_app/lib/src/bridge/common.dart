part of 'bridge_backend.dart';

Future<AuthStatus> _authStatus(BridgeBackend backend) async {
  try {
    final outcome = await backend.client.authStatus();
    return outcome.readiness == BridgeLoginReadiness.noneReady
        ? AuthStatus.signedOut
        : AuthStatus.signedIn;
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

Future<UserSummary?> _userInfo(BridgeBackend backend) async {
  try {
    final result = await backend.client.userInfo();
    final profile = result.data;
    final username = profile.username?.trim();
    if (username == null || username.isEmpty) return null;
    return UserSummary(
      username: username,
      displayName: _nonBlank(profile.name),
    );
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

Future<void> _prepareLogin(BridgeBackend backend, RoutePolicy policy) async {
  try {
    await backend.setDefaultRoutePolicy(policy);
    await backend.client.prepareLogin();
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

Future<BackendRouteSettings> _setDefaultRoutePolicy(
  BridgeBackend backend,
  RoutePolicy policy,
) async {
  try {
    final settings = await backend.client.setDefaultRoutePolicy(
      policy: _toBridgePolicy(policy),
    );
    return BackendRouteSettings(
      defaultPolicy: _toRoutePolicy(settings.defaultPolicy),
      activeRoutes: List<ConnectionMode>.unmodifiable(
        settings.activeRoutes.map(_toConnectionMode),
      ),
    );
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

Future<BackendRouteSettings> _routeSettings(BridgeBackend backend) async {
  try {
    final settings = await backend.client.routeSettings();
    return BackendRouteSettings(
      defaultPolicy: _toRoutePolicy(settings.defaultPolicy),
      activeRoutes: List<ConnectionMode>.unmodifiable(
        settings.activeRoutes.map(_toConnectionMode),
      ),
    );
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

Future<void> _login(BridgeBackend backend, LoginInput input) async {
  try {
    await backend.client.setDefaultRoutePolicy(
      policy: _toBridgePolicy(input.routePolicy),
    );
    final outcome = await backend.client.login(
      username: input.username.trim(),
      password: input.password,
    );
    if (outcome.readiness == BridgeLoginReadiness.noneReady) {
      final failed = outcome.routes
          .map((route) => route.error)
          .whereType<BridgeSafeError>()
          .firstOrNull;
      throw BackendException(_errorCode(failed?.code));
    }
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

Future<void> _logout(BridgeBackend backend) async {
  try {
    await backend.client.logout();
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

Future<void> _dispose(BridgeBackend backend) => backend.client.dispose();

Future<FeatureResult> _loadFeatureQuery(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query,
) async {
  try {
    final today = _dateOnly(query.date ?? DateTime.now());
    return await switch (feature) {
      FeatureId.schedule ||
      FeatureId.exam ||
      FeatureId.grades ||
      FeatureId.classroom => _loadAcademicFeature(
        backend,
        feature,
        query,
        today,
      ),
      FeatureId.spoc ||
      FeatureId.judge ||
      FeatureId.signin => _loadAssignmentFeature(backend, feature, query),
      FeatureId.bykc => _loadBykcFeature(backend, feature, query),
      FeatureId.libbook => _loadLibbookFeature(backend, feature, query, today),
      FeatureId.cgyy => _loadCgyyFeature(backend, feature, query, today),
      FeatureId.ygdk => _loadYgdkFeature(backend, feature, query),
      FeatureId.evaluation => _loadEvaluationFeature(backend, feature, query),
    };
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}

ConnectionMode _toConnectionMode(BridgeConnectionMode mode) => switch (mode) {
  BridgeConnectionMode.direct => ConnectionMode.direct,
  BridgeConnectionMode.webVpn => ConnectionMode.webvpn,
};

BridgeConnectionMode _toBridgeConnectionMode(ConnectionMode mode) =>
    switch (mode) {
      ConnectionMode.direct => BridgeConnectionMode.direct,
      ConnectionMode.webvpn => BridgeConnectionMode.webVpn,
    };

RoutePolicy _toRoutePolicy(BridgeRoutePolicy policy) => switch (policy) {
  BridgeRoutePolicy.auto => RoutePolicy.auto,
  BridgeRoutePolicy.direct => RoutePolicy.direct,
  BridgeRoutePolicy.webVpn => RoutePolicy.webvpn,
};

FeatureResult _countResult(
  int count,
  String unit, {
  List<FeatureDetail> details = const <FeatureDetail>[],
  FeaturePagination? pagination,
  ConnectionMode? resolvedRoute,
}) => count == 0
    ? FeatureResult.empty(resolvedRoute: resolvedRoute, pagination: pagination)
    : FeatureResult.success(
        summary: '$count$unit',
        details: details,
        pagination: pagination,
        resolvedRoute: resolvedRoute,
      );

FeaturePagination _pagination({
  required int page,
  required int size,
  required int total,
  int? totalPages,
  bool? hasMore,
}) {
  final normalizedSize = size <= 0 ? 1 : size;
  final normalizedTotal = total < 0 ? 0 : total;
  final normalizedTotalPages = totalPages != null && totalPages > 0
      ? totalPages
      : null;
  return FeaturePagination(
    page: page <= 0 ? 1 : page,
    size: normalizedSize,
    total: normalizedTotal,
    totalPages: normalizedTotalPages,
    hasMore:
        hasMore ??
        (normalizedTotalPages == null
            ? null
            : (page <= 0 ? 1 : page) < normalizedTotalPages),
  );
}

FeatureField? _field(String label, String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty
      ? null
      : FeatureField(label: label, value: trimmed);
}

List<FeatureField> _compactFields(Iterable<FeatureField?> fields) =>
    List<FeatureField>.unmodifiable(fields.whereType<FeatureField>());

String _requiredQueryValue(String? value, String label) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    throw BackendException(UbaaErrorCode.invalidInput, detail: '$label 不能为空');
  }
  return trimmed;
}

int _requiredPositiveInt(int? value, String label) {
  if (value == null || value <= 0) {
    throw BackendException(UbaaErrorCode.invalidInput, detail: '$label 必须为正整数');
  }
  return value;
}

int _requiredPositiveQueryInt(String? value, String label) {
  final trimmed = value?.trim();
  final parsed = trimmed == null ? null : int.tryParse(trimmed);
  if (parsed == null || parsed <= 0) {
    throw BackendException(UbaaErrorCode.invalidInput, detail: '$label 必须为正整数');
  }
  return parsed;
}

String _dateOnly(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

BridgeRoutePolicy _toBridgePolicy(RoutePolicy policy) => switch (policy) {
  RoutePolicy.auto => BridgeRoutePolicy.auto,
  RoutePolicy.direct => BridgeRoutePolicy.direct,
  RoutePolicy.webvpn => BridgeRoutePolicy.webVpn,
};

String? _nonBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

BackendException _mapError(BridgeError error) =>
    BackendException(_errorCode(error.code.name), detail: _safeDetail(error));

UbaaErrorCode _errorCode(String? code) => switch (code) {
  'invalidInput' || 'invalid_input' => UbaaErrorCode.invalidInput,
  'authenticationRequired' ||
  'authentication_required' => UbaaErrorCode.authenticationRequired,
  'invalidCredentials' ||
  'invalid_credentials' => UbaaErrorCode.invalidCredentials,
  'passwordRiskConfirmationFailed' || 'password_risk_confirmation_failed' =>
    UbaaErrorCode.passwordRiskConfirmationFailed,
  'permissionDenied' || 'permission_denied' => UbaaErrorCode.permissionDenied,
  'networkError' || 'network_error' => UbaaErrorCode.networkError,
  'timeout' => UbaaErrorCode.timeout,
  'upstreamUnavailable' ||
  'upstream_unavailable' => UbaaErrorCode.upstreamUnavailable,
  'upstreamChanged' || 'upstream_changed' => UbaaErrorCode.upstreamChanged,
  'parseError' || 'parse_error' => UbaaErrorCode.parseError,
  'clientDisposed' || 'client_disposed' => UbaaErrorCode.internalError,
  'confirmationRequired' ||
  'confirmation_required' => UbaaErrorCode.confirmationRequired,
  'intentExpired' || 'intent_expired' => UbaaErrorCode.intentExpired,
  'operationConflict' ||
  'operation_conflict' => UbaaErrorCode.operationConflict,
  'outcomeUnknown' || 'outcome_unknown' => UbaaErrorCode.outcomeUnknown,
  _ => UbaaErrorCode.internalError,
};

String? _safeDetail(BridgeError error) {
  final value = error.message.trim();
  if (value.isEmpty || value.length > 160) return null;
  final unsafeDetail = RegExp(
    r'(password|cookie|token|authorization|https?://)',
    caseSensitive: false,
  );
  if (value.contains(unsafeDetail)) return null;
  return value;
}

extension on Iterable<BridgeSafeError?> {
  BridgeSafeError? get firstOrNull {
    for (final value in this) {
      if (value != null) return value;
    }
    return null;
  }
}

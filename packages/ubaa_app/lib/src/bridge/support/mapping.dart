import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/backend.dart';
part 'cache_failures.dart';
part 'time.dart';

UserSummary? bridgeProfileSummary(
  BridgeUserProfile profile, {
  bool allowSchoolIdIdentity = false,
}) {
  final username =
      bridgeNonBlank(profile.username) ??
      (allowSchoolIdIdentity ? bridgeNonBlank(profile.schoolId) : null);
  if (username == null || username.isEmpty) return null;
  return UserSummary(
    username: username,
    displayName: bridgeNonBlank(profile.name),
    schoolId: bridgeNonBlank(profile.schoolId),
    email: bridgeNonBlank(profile.email),
    phone: bridgeNonBlank(profile.phone),
    idCardTypeName: bridgeNonBlank(profile.idCardTypeName),
  );
}

ConnectionMode bridgeToConnectionMode(BridgeConnectionMode mode) =>
    switch (mode) {
      BridgeConnectionMode.direct => ConnectionMode.direct,
      BridgeConnectionMode.webVpn => ConnectionMode.webvpn,
    };

BridgeConnectionMode bridgeToBridgeConnectionMode(ConnectionMode mode) =>
    switch (mode) {
      ConnectionMode.direct => BridgeConnectionMode.direct,
      ConnectionMode.webvpn => BridgeConnectionMode.webVpn,
    };

RoutePolicy bridgeToRoutePolicy(BridgeRoutePolicy policy) => switch (policy) {
  BridgeRoutePolicy.auto => RoutePolicy.auto,
  BridgeRoutePolicy.direct => RoutePolicy.direct,
  BridgeRoutePolicy.webVpn => RoutePolicy.webvpn,
};

FeatureResult bridgeCountResult(
  int count,
  String unit, {
  List<FeatureDetail> details = const <FeatureDetail>[],
  FeaturePagination? pagination,
  FeatureOverview? overview,
  ConnectionMode? resolvedRoute,
}) => count == 0
    ? FeatureResult.empty(
        resolvedRoute: resolvedRoute,
        pagination: pagination,
        overview: overview,
      )
    : FeatureResult.success(
        summary: '$count$unit',
        overview: overview,
        details: details,
        pagination: pagination,
        resolvedRoute: resolvedRoute,
      );

FeaturePagination bridgePagination({
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

FeatureField? bridgeField(String label, String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty
      ? null
      : FeatureField(label: label, value: trimmed);
}

List<FeatureField> bridgeCompactFields(Iterable<FeatureField?> fields) =>
    List<FeatureField>.unmodifiable(fields.whereType<FeatureField>());

String bridgeRequiredQueryValue(String? value, String label) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    throw BackendException(UbaaErrorCode.invalidInput, detail: '$label 不能为空');
  }
  return trimmed;
}

int bridgeRequiredPositiveInt(int? value, String label) {
  if (value == null || value <= 0) {
    throw BackendException(UbaaErrorCode.invalidInput, detail: '$label 必须为正整数');
  }
  return value;
}

int bridgeRequiredPositiveQueryInt(String? value, String label) {
  final trimmed = value?.trim();
  final parsed = trimmed == null ? null : int.tryParse(trimmed);
  if (parsed == null || parsed <= 0) {
    throw BackendException(UbaaErrorCode.invalidInput, detail: '$label 必须为正整数');
  }
  return parsed;
}

String bridgeDateOnly(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

BridgeRoutePolicy bridgeToBridgePolicy(RoutePolicy policy) => switch (policy) {
  RoutePolicy.auto => BridgeRoutePolicy.auto,
  RoutePolicy.direct => BridgeRoutePolicy.direct,
  RoutePolicy.webvpn => BridgeRoutePolicy.webVpn,
};

String? bridgeNonBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

BackendException bridgeMapError(BridgeError error) => BackendException(
  bridgeTypedErrorCode(error.code),
  cacheFailure: bridgeCacheMaintenanceFailure(error.cacheFailure),
  accountMismatch: error.code == BridgeErrorCode.cacheIdentityMismatch,
  clientDisposed: error.code == BridgeErrorCode.clientDisposed,
  kind: _typedErrorKind(error.kind),
  retryable: error.retryable,
  resolvedRoute: error.resolvedRoute == null
      ? null
      : bridgeToConnectionMode(error.resolvedRoute!),
);

UbaaErrorCode bridgeTypedErrorCode(BridgeErrorCode code) => switch (code) {
  BridgeErrorCode.invalidInput => UbaaErrorCode.invalidInput,
  BridgeErrorCode.cacheIdentityMismatch ||
  BridgeErrorCode.authenticationRequired =>
    UbaaErrorCode.authenticationRequired,
  BridgeErrorCode.invalidCredentials => UbaaErrorCode.invalidCredentials,
  BridgeErrorCode.passwordRiskConfirmationFailed =>
    UbaaErrorCode.passwordRiskConfirmationFailed,
  BridgeErrorCode.permissionDenied => UbaaErrorCode.permissionDenied,
  BridgeErrorCode.networkError => UbaaErrorCode.networkError,
  BridgeErrorCode.timeout => UbaaErrorCode.timeout,
  BridgeErrorCode.upstreamUnavailable => UbaaErrorCode.upstreamUnavailable,
  BridgeErrorCode.upstreamChanged => UbaaErrorCode.upstreamChanged,
  BridgeErrorCode.parseError => UbaaErrorCode.parseError,
  BridgeErrorCode.internalError ||
  BridgeErrorCode.clientDisposed => UbaaErrorCode.internalError,
  BridgeErrorCode.confirmationRequired => UbaaErrorCode.confirmationRequired,
  BridgeErrorCode.intentExpired => UbaaErrorCode.intentExpired,
  BridgeErrorCode.operationConflict => UbaaErrorCode.operationConflict,
  BridgeErrorCode.outcomeUnknown => UbaaErrorCode.outcomeUnknown,
};

UbaaErrorKind _typedErrorKind(BridgeErrorKind kind) => switch (kind) {
  BridgeErrorKind.input => UbaaErrorKind.input,
  BridgeErrorKind.authentication => UbaaErrorKind.authentication,
  BridgeErrorKind.network => UbaaErrorKind.network,
  BridgeErrorKind.upstream => UbaaErrorKind.upstream,
  BridgeErrorKind.parse => UbaaErrorKind.parse,
  BridgeErrorKind.internal => UbaaErrorKind.internal,
};

UbaaErrorKind bridgeSafeErrorKind(String value) => switch (value) {
  'input' => UbaaErrorKind.input,
  'authentication' => UbaaErrorKind.authentication,
  'network' => UbaaErrorKind.network,
  'upstream' => UbaaErrorKind.upstream,
  'parse' => UbaaErrorKind.parse,
  'internal' => UbaaErrorKind.internal,
  _ => UbaaErrorKind.unknown,
};

UbaaErrorCode bridgeErrorCode(String? code) => switch (code) {
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

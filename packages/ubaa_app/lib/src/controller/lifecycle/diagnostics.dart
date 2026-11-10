import 'dart:async';

import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

import '../../contracts/app_service.dart';
import '../error_mapper.dart';
import '../state/state.dart';

mixin ControllerDiagnostics on ControllerState {
  final _startup = Stopwatch()..start();
  Stopwatch? _authentication;
  final _shownErrors = Expando<bool>();
  final _errorSources = Expando<String>();
  final _expiredRoutes = <(FeatureId, ConnectionMode?)>{};
  bool _started = false;
  bool _coldStart = false;
  bool _firstContent = false;

  @internal
  UiError internalRecordFailure(
    Object cause,
    DiagnosticOperation operation, {
    StackTrace? stackTrace,
    FeatureId? feature,
    Duration? latency,
  }) {
    final error = UbaaErrorMapper.fromObject(cause);
    if (internalDisposed) return error;
    try {
      final recorded = internalDiagnostics.record(
        operation: operation,
        error: error,
        feature: feature,
        latency: latency,
        cause: cause,
        stackTrace: stackTrace,
      );
      if (telemetrySource(stackTrace) case final source?
          when operation != DiagnosticOperation.telemetry) {
        _errorSources[recorded] = source;
      }
      return recorded;
    } on Object {
      // 诊断失败不覆盖业务结果，也不产生遥测。
      return error;
    }
  }

  @internal
  Future<void> internalRecordAppOpen() async {
    if (_started || !telemetryEnabled || internalDisposed) return;
    _started = true;
    await internalTrackTelemetry(TelemetryEvents.appStarted);
  }

  @internal
  void internalRecordColdStart() {
    if (_coldStart || internalDisposed) return;
    _coldStart = true;
    _timing(TelemetryMetrics.coldStart, 'app', null, _startup.elapsed);
  }

  @internal
  void internalRecordFirstContent() {
    if (_firstContent || internalDisposed) return;
    _firstContent = true;
    _timing(TelemetryMetrics.firstContent, 'app', null, _startup.elapsed);
  }

  @internal
  void internalBeginAuthTelemetry() {
    if (internalBackend case final ConfirmedAppServiceAccountBackend service) {
      service.clearAppServiceAccount();
    }
    _authentication = Stopwatch()..start();
    _counter(TelemetryEvents.authStarted, 'auth');
  }

  @internal
  void internalCancelAuthTelemetry() {
    _authentication = null;
  }

  @internal
  void internalEndAuthTelemetry({
    UiError? error,
    ConnectionMode? route,
    StackTrace? stackTrace,
  }) {
    final elapsed = _authentication?.elapsed;
    _authentication = null;
    if (elapsed == null) return;
    final resolved = error?.resolvedRoute ?? route;
    if (error == null) {
      _expiredRoutes.clear();
      _counter(TelemetryEvents.authSucceeded, 'auth', route: resolved);
    } else {
      _error(
        TelemetryEvents.authFailed,
        'auth',
        error,
        route: resolved,
        stackTrace: stackTrace,
      );
    }
    _resolved('auth', resolved, error == null);
    _timing(TelemetryMetrics.auth, 'auth', resolved, elapsed);
  }

  @internal
  void internalRecordSessionExpired(FeatureId feature, ConnectionMode? route) {
    if (route == null && _expiredRoutes.any((entry) => entry.$1 == feature))
      return;
    if (route != null && _expiredRoutes.remove((feature, null))) {
      _expiredRoutes.add((feature, route));
      return;
    }
    if (!_expiredRoutes.add((feature, route))) return;
    _counter(
      TelemetryEvents.sessionExpired,
      feature.wireName,
      route: route,
      result: 'failure',
    );
  }

  @internal
  void internalRecordVisibleError(UiError error) {
    if (_shownErrors[error] == true) return;
    _shownErrors[error] = true;
    _error(TelemetryEvents.uiErrorShown, 'app', error);
  }

  @internal
  Future<void> internalRecordFeature(
    FeatureId feature, {
    bool success = false,
    bool empty = false,
    UiError? error,
    Duration? latency,
    ConnectionMode? route,
    StackTrace? stackTrace,
  }) async {
    final name = feature.wireName;
    final resolved = error?.resolvedRoute ?? route;
    if (error == null) {
      _expiredRoutes.removeWhere(
        (entry) =>
            entry.$1 == feature &&
            (resolved == null || entry.$2 == resolved || entry.$2 == null),
      );
      _counter(
        TelemetryEvents.featureLoaded,
        name,
        route: resolved,
        result: success
            ? 'success'
            : empty
            ? 'empty'
            : 'failure',
      );
    } else {
      _error(
        TelemetryEvents.featureFailed,
        name,
        error,
        route: resolved,
        stackTrace: stackTrace,
      );
      if (error.code == UbaaErrorCode.authenticationRequired &&
          resolved != null) {
        internalRecordSessionExpired(feature, resolved);
      }
    }
    _resolved(name, resolved, error == null);
    if (latency != null) {
      _timing(TelemetryMetrics.featureLoad, name, resolved, latency);
    }
  }

  void _resolved(String feature, ConnectionMode? route, bool success) {
    if (route != null) {
      _counter(
        TelemetryEvents.routeResolved,
        feature,
        route: route,
        result: success ? 'success' : 'failure',
      );
    }
  }

  void _counter(
    String event,
    String feature, {
    ConnectionMode? route,
    String result = 'success',
  }) => unawaited(
    internalTrackTelemetry(
      event,
      properties: {
        'feature': feature,
        'route': route?.name ?? 'none',
        'result': result,
      },
    ),
  );

  void _error(
    String event,
    String feature,
    UiError error, {
    ConnectionMode? route,
    StackTrace? stackTrace,
  }) => unawaited(
    internalTrackTelemetry(
      event,
      properties: {
        'feature': feature,
        'route': (error.resolvedRoute ?? route)?.name ?? 'none',
        'error_code': error.code.wireName,
        'error_kind': error.kind == UbaaErrorKind.unknown
            ? 'internal'
            : error.kind.name,
        'retryable': error.retryable,
        if ((telemetrySource(stackTrace) ?? _errorSources[error])
            case final source?)
          'source': source,
      },
    ),
  );

  void _timing(
    String metric,
    String feature,
    ConnectionMode? route,
    Duration elapsed,
  ) => unawaited(
    internalTrackTelemetry(
      metric,
      properties: {
        'feature': feature,
        'route': route?.name ?? 'none',
        'bucket': TelemetryMetrics.bucket(elapsed),
      },
    ),
  );

  @internal
  Future<void> internalTrackTelemetry(
    String event, {
    Map<String, Object?> properties = const {},
  }) async {
    if (internalDisposed) return;
    final epoch = internalLifecycleEpoch;
    final backend = internalBackend;
    void failed() {
      if (!internalDisposed &&
          epoch == internalLifecycleEpoch &&
          identical(backend, internalBackend)) {
        internalRecordFailure(
          StateError('遥测入队未完成'),
          DiagnosticOperation.telemetry,
        );
      }
    }

    if (backend case final AppServiceBackend service) {
      // GUI 和命令进程共享状态；每次入队由 Core 重新读取许可。
      await CallbackTelemetryClient(
        sink: service.recordAppService,
        onFailure: failed,
      ).track(event, properties: properties);
    } else if (internalTelemetryEnabled) {
      try {
        await internalTelemetry
            .track(event, properties: properties)
            .timeout(const Duration(seconds: 2));
      } on Object {
        failed();
      }
    }
  }
}

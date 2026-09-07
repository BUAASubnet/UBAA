part of '../app_controller.dart';

extension _AppControllerDiagnostics on AppController {
  UiError _recordFailure(
    Object cause,
    DiagnosticOperation operation, {
    StackTrace? stackTrace,
    FeatureId? feature,
    Duration? latency,
  }) {
    final error = UbaaErrorMapper.fromObject(cause);
    if (_disposed) return error;
    try {
      return _diagnostics.record(
        operation: operation,
        error: error,
        feature: feature,
        latency: latency,
        cause: cause,
        stackTrace: stackTrace,
      );
    } on Object {
      // 可选诊断失败不覆盖原业务错误，也不递归记录自身故障。
      return error;
    }
  }

  Future<void> _recordAppOpen() async {
    if (_telemetryEnabled)
      unawaited(_trackTelemetry(TelemetryEvents.appStarted));
  }

  Future<void> _recordFeature(
    FeatureId feature, {
    bool success = false,
    bool empty = false,
    UiError? error,
    Duration? latency,
  }) async {
    if (!_telemetryEnabled) return;
    unawaited(
      _trackTelemetry(
        error == null
            ? TelemetryEvents.featureLoaded
            : TelemetryEvents.featureFailed,
        properties: {
          'feature': feature.wireName,
          'result': success
              ? 'success'
              : empty
              ? 'empty'
              : 'failure',
          if (error != null) 'error_code': error.code.wireName,
          if (error != null) 'error_kind': error.kind.name,
          if (error != null) 'retryable': error.retryable,
          if (error?.resolvedRoute != null) 'route': error!.resolvedRoute!.name,
          if (latency != null) 'source': _latencyBucket(latency),
        },
      ),
    );
  }

  Future<void> _trackTelemetry(
    String event, {
    Map<String, Object?> properties = const {},
  }) async {
    final epoch = _lifecycleEpoch;
    try {
      // 遥测不阻塞业务；截止预算限制失效 sink 对控制器生命周期的持有。
      await _telemetry
          .track(event, properties: properties)
          .timeout(const Duration(seconds: 2));
    } on Object catch (error, stackTrace) {
      if (epoch == _lifecycleEpoch) {
        _recordFailure(
          error,
          DiagnosticOperation.telemetry,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _flushTelemetry() async {
    final epoch = _lifecycleEpoch;
    try {
      await _telemetry.flush().timeout(const Duration(seconds: 2));
    } on Object catch (error, stackTrace) {
      if (epoch == _lifecycleEpoch) {
        _recordFailure(
          error,
          DiagnosticOperation.telemetry,
          stackTrace: stackTrace,
        );
      }
    }
  }

  String _latencyBucket(Duration latency) {
    if (latency < const Duration(milliseconds: 500)) return 'lt_500ms';
    if (latency < const Duration(seconds: 2)) return '500ms_2s';
    if (latency < const Duration(seconds: 5)) return '2s_5s';
    return 'gte_5s';
  }
}

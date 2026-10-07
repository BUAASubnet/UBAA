import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../state/state.dart' show ControllerState;

mixin ControllerDiagnostics on ControllerState {
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
      return internalDiagnostics.record(
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

  @internal
  Future<void> internalRecordAppOpen() async {
    if (internalTelemetryEnabled)
      unawaited(internalTrackTelemetry(TelemetryEvents.appStarted));
  }

  @internal
  Future<void> internalRecordFeature(
    FeatureId feature, {
    bool success = false,
    bool empty = false,
    UiError? error,
    Duration? latency,
  }) async {
    if (!internalTelemetryEnabled) return;
    unawaited(
      internalTrackTelemetry(
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
          if (latency != null) 'source': internalLatencyBucket(latency),
        },
      ),
    );
  }

  @internal
  Future<void> internalTrackTelemetry(
    String event, {
    Map<String, Object?> properties = const {},
  }) async {
    final epoch = internalLifecycleEpoch;
    try {
      // 遥测不阻塞业务；截止预算限制失效 sink 对控制器生命周期的持有。
      await internalTelemetry
          .track(event, properties: properties)
          .timeout(const Duration(seconds: 2));
    } on Object catch (error, stackTrace) {
      if (epoch == internalLifecycleEpoch) {
        internalRecordFailure(
          error,
          DiagnosticOperation.telemetry,
          stackTrace: stackTrace,
        );
      }
    }
  }

  @internal
  Future<void> internalFlushTelemetry() async {
    final epoch = internalLifecycleEpoch;
    try {
      await internalTelemetry.flush().timeout(const Duration(seconds: 2));
    } on Object catch (error, stackTrace) {
      if (epoch == internalLifecycleEpoch) {
        internalRecordFailure(
          error,
          DiagnosticOperation.telemetry,
          stackTrace: stackTrace,
        );
      }
    }
  }

  @internal
  String internalLatencyBucket(Duration latency) {
    if (latency < const Duration(milliseconds: 500)) return 'lt_500ms';
    if (latency < const Duration(seconds: 2)) return '500ms_2s';
    if (latency < const Duration(seconds: 5)) return '2s_5s';
    return 'gte_5s';
  }
}

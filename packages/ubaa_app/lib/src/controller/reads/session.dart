import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/progressive.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/recovery.dart';
import '../state/models.dart' show RecoveryRequest;
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show SessionRecoveryStatus;
import 'lanes.dart';

mixin ControllerScheduledSession on ControllerState {
  @internal
  bool get internalHasScheduledTargetRecovery =>
      internalBackend is ProgressiveReadBackend &&
      internalBackend is RequiredSessionBackend;

  @internal
  bool get internalLegacyReadSessionBlocked =>
      internalUsesLocalRecovery &&
      !internalHasScheduledTargetRecovery &&
      internalSessionRecoveryStatus != SessionRecoveryStatus.ready;

  @internal
  bool get internalReadTransitionBlocked =>
      internalWriteTransitions != 0 &&
      !(internalHasScheduledTargetRecovery && internalActiveRecovery != null);

  @internal
  Future<void> internalEnsureReadTarget(
    FeatureId feature, {
    bool force = false,
  }) async {
    if (!internalUsesLocalRecovery) return;
    if (internalBackend is! RequiredSessionBackend) {
      await internalRequireReadSession(feature: feature);
      return;
    }
    if (force || recoveryStatusFor(feature) != SessionRecoveryStatus.ready) {
      await internalRecoverSession(feature: feature, refreshHomeAfter: false);
    }
    if (internalDisposed || internalIsSigningOut) throw const ReadCancelled();
    final status = recoveryStatusFor(feature);
    if (status == SessionRecoveryStatus.ready) return;
    if (internalFeatureRecoveryErrors[feature] case final error?)
      throw BackendException.fromUi(error);
    throw BackendException(
      status == SessionRecoveryStatus.unavailable
          ? UbaaErrorCode.networkError
          : UbaaErrorCode.authenticationRequired,
    );
  }

  @internal
  bool internalReadTargetNeedsRecovery(FeatureId feature) =>
      internalUsesLocalRecovery &&
      (internalBackend is RequiredSessionBackend
          ? recoveryStatusFor(feature) != SessionRecoveryStatus.ready
          : internalSessionRecoveryStatus != SessionRecoveryStatus.ready);

  @internal
  Future<void> internalScheduleReadAuthentication(
    FeatureId feature,
    ReadPriority priority,
    bool Function() current, {
    bool force = false,
    ReadDemand? demand,
  }) {
    if (!force && !internalReadTargetNeedsRecovery(feature))
      return Future.value();
    return internalReadScheduler.run(
      priority,
      current,
      () => internalEnsureReadTarget(feature, force: force),
      demand: demand,
    );
  }

  @internal
  Future<T> internalScheduledRead<T>(
    FeatureId feature,
    ReadPriority priority,
    bool Function() current,
    Future<T> Function() operation, {
    void Function(T)? discard,
    bool writeReadback = false,
    ReadDemand? demand,
  }) async {
    if (writeReadback)
      return internalReadScheduler.run(
        priority,
        current,
        operation,
        discard: discard,
        continuation: true,
      );
    final recovered = internalReadTargetNeedsRecovery(feature);
    if (recovered)
      await internalScheduleReadAuthentication(
        feature,
        priority,
        current,
        demand: demand,
      );
    try {
      return await internalReadScheduler.run(
        priority,
        current,
        operation,
        discard: discard,
        continuation: recovered && internalBackend is! ConcurrentReadBackend,
        demand: demand,
        lane: controllerReadLane(internalBackend, feature),
      );
    } on BackendException catch (error) {
      if (error.code != UbaaErrorCode.authenticationRequired ||
          error.accountMismatch ||
          !internalHasScheduledTargetRecovery)
        rethrow;
      internalFeatureRecoveryStates[feature] = SessionRecoveryStatus.needsLogin;
      // 只读请求最多恢复一次；认证错误、缺材料或第二次读取失败直接交付。
      await internalScheduleReadAuthentication(
        feature,
        priority,
        current,
        force: true,
        demand: demand,
      );
      return internalReadScheduler.run(
        priority,
        current,
        operation,
        discard: discard,
        continuation: true,
        demand: demand,
        lane: controllerReadLane(internalBackend, feature),
      );
    }
  }

  @internal
  void internalInvalidateReadPlansAfterLogin(RecoveryRequest request) {
    if (!request.replacedAllRoutes && request.replacedRoute == null) return;
    for (final scope in internalReadScopes) {
      if (scope.task != null &&
          scope.valid &&
          (request.replacedAllRoutes ||
              scope.route == null ||
              scope.route == request.replacedRoute)) {
        scope.restartRequested = true;
        scope.task!.cancel();
      }
    }
  }
}

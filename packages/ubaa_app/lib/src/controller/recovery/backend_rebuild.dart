import 'dart:async';
import '../../backend/unavailable.dart';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import '../state/models.dart' show RecoveryRequest;
import '../state/state.dart' show ControllerState;

mixin ControllerBackendRecovery on ControllerState {
  @internal
  Future<bool> internalRebuildDuringRecovery(RecoveryRequest request) async {
    final factory = internalBackendFactory;
    if (factory == null ||
        !internalAppForeground ||
        internalRebuildingBackend ||
        internalClearingBusinessCache ||
        internalIsSigningOut ||
        !internalRecoveryIsCurrent(request.epoch) ||
        !identical(internalActiveRecovery, request) ||
        !internalActivities.onlyRecovery ||
        internalWriteCoordinator.hasPendingOperation)
      return false;
    final shared = internalSharedRecoveryScope;
    await shared?.validateSharedState();
    if (!internalRecoveryIsCurrent(request.epoch) || internalIsSigningOut)
      return false;
    internalSessionLifecycle.beginRebuild();
    final previous = internalBackend;
    final previousAccount = internalLocalAccount;
    try {
      if (previous is AgendaProvider) {
        try {
          await internalCloseAgenda();
        } on Object catch (error, stackTrace) {
          internalRecordFailure(
            error,
            DiagnosticOperation.disposal,
            stackTrace: stackTrace,
          );
        }
      }
      await shared?.validateSharedState();
      final replacement = await factory();
      try {
        await shared?.validateSharedState();
      } on Object {
        await internalDisposeBackendOnce(replacement);
        rethrow;
      }
      if (replacement is UnavailableBackend) {
        throw InitializationException(replacement.failure);
      }
      if (!internalRecoveryIsCurrent(request.epoch) || internalIsSigningOut) {
        await internalDisposeBackendOnce(replacement);
        return false;
      }
      if (identical(previous, replacement))
        throw const BackendException(UbaaErrorCode.internalError);
      internalInvalidateReadsForRebuild(request);
      internalFeatureRecoveryStates.clear();
      internalFeatureRecoveryErrors.clear();
      internalRecoveredRoute = null;
      internalActiveRoutes = const [];
      internalPreserveReadonlyAfterRebuild();
      internalNotify();
      try {
        await internalDisposeBackendOnce(previous);
      } on Object catch (error, stackTrace) {
        internalRecordFailure(
          error,
          DiagnosticOperation.disposal,
          stackTrace: stackTrace,
        );
      }
      if (!internalRecoveryIsCurrent(request.epoch) || internalIsSigningOut) {
        try {
          await internalDisposeBackendOnce(replacement);
        } on Object {
          // 退出/销毁的原错误不被继任实例释放错误替换。
        }
        return false;
      }
      // 释放旧实例期间页面仍可操作；此时新排队的查询也须交给继任实例。
      internalInvalidateReadsForRebuild(request);
      try {
        await shared?.validateSharedState();
      } on Object {
        await internalDisposeBackendOnce(replacement);
        rethrow;
      }
      if (!internalRecoveryIsCurrent(request.epoch) || internalIsSigningOut) {
        await internalDisposeBackendOnce(replacement);
        return false;
      }
      if (shared?.sharedSnapshot != null)
        internalSharedAccountSnapshot = shared!.sharedSnapshot;
      internalSessionLifecycle.replaceBackend(replacement);
      internalReplaceWriteCoordinator(replacement);
      internalProfileRefreshedEpoch = -1;
      internalProfileFailureEpoch = -1;
      internalProfileRequest = null;
      internalSessionLifecycle.endRebuild();
      final account = internalLocalAccount;
      if (account != null) unawaited(internalRestoreCachedHome(account));
      return true;
    } finally {
      internalSessionLifecycle.endRebuild();
      // 工厂失败或返回原对象时，本地日程仍独立于网络客户端恢复。
      if (previous is AgendaProvider &&
          identical(previous, internalBackend) &&
          !internalDisposed &&
          !internalIsSigningOut &&
          previousAccount != null &&
          internalLocalAccount?.id == previousAccount.id) {
        internalOpenAgenda(previousAccount);
      }
      internalNotify();
    }
  }

  @internal
  void internalInvalidateReadsForRebuild(RecoveryRequest request) {
    for (final scope in internalReadScopes.toList()) {
      if (scope.valid && scope.query != null)
        request.queriesAfterRebuild[scope.feature] = scope.query!;
      scope.cancel();
    }
    internalCancelDeferredRecovery();
    request.epoch = internalSessionLifecycle.invalidate();
    internalCacheLifecycle.invalidateOffline();
    internalCacheLifecycle.invalidateReads();
    internalYgdkGeneration++;
  }

  @internal
  void internalPreserveReadonlyAfterRebuild() {
    for (final snapshots in [internalSnapshots, internalHomeDefaults]) {
      for (final feature in FeatureId.values) {
        final old = snapshots[feature]!;
        final hasContent =
            old.details.isNotEmpty ||
            old.overview != null ||
            old.evidence != null;
        snapshots[feature] = old.copyWith(
          status: hasContent ? FeatureLoadStatus.stale : FeatureLoadStatus.idle,
          details: readonlyFeatureDetails(old.details),
          overview: readonlyFeatureOverview(old.overview),
        );
      }
    }
    internalReadCaches.invalidate();
    internalYgdkReadbackState = const YgdkReadbackState.empty();
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/progressive.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import '../state/models.dart'
    show FeatureReadStart, ProgressiveScope, ReadPlanRestart;
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase, SessionRecoveryStatus;

mixin ControllerProgressive on ControllerState {
  @internal
  Future<void>? internalPendingFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) {
    if (internalBackend is! ProgressiveReadBackend) return null;
    for (final scope in internalReadScopes) {
      if (scope.feature == feature &&
          scope.valid &&
          FeatureReadContext(
            query: scope.query,
            requestRevision: 0,
          ).hasSameQuery(query))
        return scope.completion.future;
    }
    return null;
  }

  @internal
  Future<FeatureResult> internalScheduleAuxiliaryRead(
    UbaaBackend backend,
    FeatureId feature,
    ReadPriority priority,
    bool Function() current,
    Future<FeatureResult> Function() operation, {
    ReadDemand? demand,
  }) async {
    try {
      return await (backend is ProgressiveReadBackend
          ? internalScheduledRead(
              feature,
              priority,
              current,
              operation,
              demand: demand,
            )
          : Future<FeatureResult>.sync(operation));
    } on BackendException catch (error) {
      // 辅助读取同样绑定账号；普通认证失败可以保旧，明确串号必须关闭。
      if (error.accountMismatch && current())
        await internalRejectMismatchedAccount();
      rethrow;
    }
  }

  @internal
  bool internalCanRunScheduledRead(ReadPriority priority) {
    if (internalDisposed ||
        internalIsSigningOut ||
        (internalPhase != AppPhase.home &&
            !(!internalInitialized && internalPhase == AppPhase.splash)) ||
        isLoggingIn ||
        internalRebuildingBackend ||
        internalWriteTransitions != 0 ||
        internalInteractiveEngaged ||
        (internalUsesLocalRecovery &&
            !internalHomeFrameReported &&
            internalSessionRecoveryStatus == SessionRecoveryStatus.idle))
      return false;
    if (priority == ReadPriority.writeReadback) return true;
    return internalAppForeground &&
        !internalWriteCoordinator.hasPendingOperation &&
        internalActiveRecovery == null &&
        internalQueuedRecoveries.isEmpty;
  }

  @internal
  void internalPumpReadTasks() {
    internalPruneScheduleImports();
    for (final scope in internalReadScopes.toList()) {
      if (!scope.current()) scope.cancel();
    }
    internalReadScheduler.pump();
    internalDrainWriteRefreshes();
  }

  @internal
  void internalCancelSegmentedReadScopes(FeatureId feature) {
    if (internalBackend is! ProgressiveReadBackend ||
        (feature != FeatureId.judge &&
            feature != FeatureId.spoc &&
            feature != FeatureId.evaluation))
      return;
    for (final scope
        in internalReadScopes
            .where((value) => value.feature == feature)
            .toList()) {
      scope.cancel();
      if (scope.query == null) {
        final previous = internalHomeDefaults[feature]!;
        internalHomeDefaults[feature] = previous.copyWith(
          status: previous.details.isEmpty && previous.evidence == null
              ? FeatureLoadStatus.idle
              : FeatureLoadStatus.stale,
        );
      }
    }
  }

  @internal
  Future<FeatureResult> internalReadScheduledFeature(
    FeatureId feature,
    FeatureQuery? query,
    ProgressiveScope scope, {
    required bool writeReadback,
    required void Function(FeatureReadBatch) onBatch,
  }) async {
    final backend = internalBackend;
    if (!writeReadback &&
        backend is ProgressiveReadBackend &&
        feature == FeatureId.grades &&
        query != null) {
      final shared = internalReadSharedGradeQuery(query);
      if (shared != null) return shared;
    }
    Future<FeatureResult> ordinary() {
      if (writeReadback &&
          feature == FeatureId.libbook &&
          backend is LibbookReadbackBackend) {
        return (backend as LibbookReadbackBackend).readLibbookAfterWrite(
          query ?? const FeatureQuery(),
        );
      }
      if (writeReadback &&
          feature == FeatureId.cgyy &&
          backend is CgyyReservationReadbackBackend) {
        return (backend as CgyyReservationReadbackBackend).readCgyyAfterWrite(
          query ?? const FeatureQuery(),
        );
      }
      if (writeReadback &&
          feature == FeatureId.bykc &&
          backend is BykcReadbackBackend) {
        return (backend as BykcReadbackBackend).readBykcAfterWrite(
          query ?? const FeatureQuery(),
        );
      }
      if (writeReadback &&
          feature == FeatureId.signin &&
          backend is SigninReadbackBackend) {
        return (backend as SigninReadbackBackend).readSigninAfterWrite();
      }
      return switch ((backend, query)) {
        (FeatureQueryBackend queries, final FeatureQuery value) =>
          queries.loadFeatureQuery(feature, value),
        _ => backend.loadFeature(feature),
      };
    }

    if (backend is! ProgressiveReadBackend) {
      if (internalInteractiveEngaged) {
        return internalReadScheduler.run(
          ReadPriority.interactive,
          () => scope.valid,
          ordinary,
        );
      }
      return ordinary();
    }
    final priority = writeReadback
        ? ReadPriority.writeReadback
        : query == null
        ? ReadPriority.home
        : feature == FeatureId.signin
        ? ReadPriority.urgent
        : ReadPriority.interactive;
    if (writeReadback)
      return internalScheduledRead(
        feature,
        priority,
        () => scope.valid,
        ordinary,
        writeReadback: true,
      );
    var restarted = false;
    while (scope.valid) {
      scope.restartRequested = false;
      final start = await internalScheduledRead(
        feature,
        priority,
        () => scope.valid,
        () async {
          final account = internalLocalAccount;
          final task =
              backend is AccountScopedProgressiveReadBackend && account != null
              ? await (backend as AccountScopedProgressiveReadBackend)
                    .beginAccountFeatureRead(feature, query, account)
              : await (backend as ProgressiveReadBackend).beginFeatureRead(
                  feature,
                  query,
                );
          return task == null
              ? FeatureReadStart(result: await ordinary())
              : FeatureReadStart(task: task);
        },
        discard: (start) => start.task?.cancel(),
      );
      final task = start.task;
      if (task == null) return start.result!;
      scope.task = task;
      try {
        while (scope.valid) {
          final batchPriority = query == null
              ? ReadPriority.background
              : priority;
          await internalScheduleReadAuthentication(
            feature,
            batchPriority,
            () => scope.valid,
          );
          if (scope.restartRequested) throw const ReadPlanRestart();
          FeatureReadBatch batch;
          try {
            batch = await internalReadScheduler.run(
              batchPriority,
              () => scope.valid,
              () {
                if (scope.restartRequested) throw const ReadPlanRestart();
                return task.next();
              },
            );
          } on BackendException catch (error) {
            if (scope.restartRequested) throw const ReadPlanRestart();
            if (restarted ||
                error.accountMismatch ||
                error.code != UbaaErrorCode.authenticationRequired ||
                !internalHasScheduledTargetRecovery)
              rethrow;
            internalFeatureRecoveryStates[feature] =
                SessionRecoveryStatus.needsLogin;
            await internalScheduleReadAuthentication(
              feature,
              batchPriority,
              () => scope.valid,
              force: true,
            );
            throw const ReadPlanRestart();
          }
          if (scope.restartRequested) throw const ReadPlanRestart();
          scope.route = batch.result.resolvedRoute ?? scope.route;
          if (batch.finished) return batch.result;
          if (batch.publish) onBatch(batch);
        }
        throw const ReadCancelled();
      } on ReadPlanRestart {
        if (restarted)
          throw const BackendException(
            UbaaErrorCode.operationConflict,
            retryable: true,
          );
        restarted = true;
      } finally {
        task.cancel();
        scope.task = null;
      }
    }
    throw const ReadCancelled();
  }
}

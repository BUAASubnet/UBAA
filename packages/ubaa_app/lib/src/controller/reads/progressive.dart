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
import 'lanes.dart';

mixin ControllerProgressive on ControllerState {
  @internal
  Future<void>? internalPendingFeatureRead(
    FeatureId feature,
    FeatureQuery? query, {
    bool firstBatch = false,
  }) {
    if (internalBackend is! ProgressiveReadBackend) return null;
    for (final scope in internalReadScopes) {
      if (scope.feature == feature &&
          scope.valid &&
          FeatureReadContext(
            query: scope.query,
            requestRevision: 0,
          ).hasSameQuery(query)) {
        if (internalSchoolPrompt case final report?) {
          scope.joinedSchoolPrompts.add(report);
        }
        return firstBatch ? scope.firstResult.future : scope.completion.future;
      }
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
        // 单项目标会话恢复是读取的前置步骤，与其他读取同样放行在途批次。
        internalReadTransitionBlocked ||
        internalInteractiveEngaged ||
        (internalUsesLocalRecovery &&
            !internalHomeFrameReported &&
            internalSessionRecoveryStatus == SessionRecoveryStatus.idle))
      return false;
    if (priority == ReadPriority.writeReadback) return true;
    if (internalNetworkChecking) return false;
    return internalAppForeground &&
        !internalWriteCoordinator.hasPendingOperation &&
        (internalTargetRecoveryOnly ||
            (internalActiveRecovery == null &&
                internalQueuedRecoveries.isEmpty));
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
    scope.writeReadback = writeReadback;
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
    final requestQuery =
        feature == FeatureId.judge && internalSchoolPrompt != null
        ? (query ?? const FeatureQuery()).copyWith(refreshIndices: true)
        : query;
    var authenticationRetried = false;
    while (scope.valid) {
      scope.restartRequested = false;
      FeatureReadTask? task;
      try {
        final start = await internalScheduledRead(
          feature,
          priority,
          () => scope.valid,
          () async {
            scope.preparing = true;
            try {
              final account = internalLocalAccount;
              final prepared =
                  backend is AccountScopedProgressiveReadBackend &&
                      account != null
                  ? await (backend as AccountScopedProgressiveReadBackend)
                        .beginAccountFeatureRead(feature, requestQuery, account)
                  : await (backend as ProgressiveReadBackend).beginFeatureRead(
                      feature,
                      requestQuery,
                    );
              if (scope.restartRequested) {
                prepared?.cancel();
                throw const ReadPlanRestart();
              }
              scope.task = prepared;
              return prepared == null
                  ? FeatureReadStart(result: await ordinary())
                  : FeatureReadStart(task: prepared);
            } on BackendException catch (error) {
              if (scope.restartRequested && !error.accountMismatch)
                throw const ReadPlanRestart();
              rethrow;
            } finally {
              scope.preparing = false;
            }
          },
          discard: (start) => start.task?.cancel(),
        );
        final activeTask = start.task;
        task = activeTask;
        if (scope.restartRequested) throw const ReadPlanRestart();
        if (activeTask == null) return start.result!;
        scope.task = activeTask;
        // 首次结果之前允许少量准备步骤连续执行，避免空白作业区等待慢来源。
        // 预算耗尽或已发布首批后让位，不能让异常计划一直占用首页队列。
        var homeBootstrapBatches = scope.firstResult.isCompleted ? 0 : 3;
        while (scope.valid) {
          final homeBootstrap = query == null && homeBootstrapBatches > 0;
          final batchPriority = query == null && !homeBootstrap
              ? ReadPriority.background
              : priority;
          if (internalReadTargetNeedsRecovery(feature)) {
            await internalScheduleReadAuthentication(
              feature,
              batchPriority,
              () => scope.valid,
            );
          }
          if (scope.restartRequested) throw const ReadPlanRestart();
          FeatureReadBatch batch;
          try {
            batch = await internalReadScheduler.run(
              batchPriority,
              () => scope.valid,
              () {
                if (scope.restartRequested) throw const ReadPlanRestart();
                return activeTask.next();
              },
              continuation: homeBootstrap,
              lane: controllerReadLane(backend, feature),
            );
          } on BackendException catch (error) {
            if (error.accountMismatch) rethrow;
            if (scope.restartRequested) throw const ReadPlanRestart();
            if (authenticationRetried ||
                error.code != UbaaErrorCode.authenticationRequired ||
                !internalHasScheduledTargetRecovery)
              rethrow;
            internalRecordSessionExpired(feature, error.resolvedRoute);
            authenticationRetried = true;
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
          homeBootstrapBatches = batch.publish ? 0 : homeBootstrapBatches - 1;
          scope.route = batch.result.resolvedRoute ?? scope.route;
          if (batch.finished) return batch.result;
          if (batch.publish) onBatch(batch);
        }
        throw const ReadCancelled();
      } on ReadPlanRestart {
        // 仅已核验登录替换或本次认证恢复可请求重建；新登录各自使旧计划失效。
      } finally {
        task?.cancel();
        scope.task = null;
      }
    }
    throw const ReadCancelled();
  }
}

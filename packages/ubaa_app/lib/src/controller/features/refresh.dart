import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/progressive.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import 'package:ubaa_app/src/contracts/recovery.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../reads/judge_projection.dart' show controllerRetainJudgePartial;
import '../state/models.dart'
    show ProgressiveScope, controllerHomeDefaultFeatures;
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show SessionRecoveryStatus;

mixin ControllerRefresh on ControllerState {
  @internal
  Future<void> internalRefreshHome({
    Iterable<FeatureId>? only,
    bool writeReadback = false,
  }) async {
    if (internalDisposed || internalClearingBusinessCache) return;
    final joining = <Future<void>>[];
    final features = <FeatureId>[];
    for (final feature in (only ?? controllerHomeDefaultFeatures).toSet()) {
      final pending = writeReadback
          ? null
          : internalPendingFeatureRead(feature, null);
      if (pending != null) {
        joining.add(pending);
      } else {
        features.add(feature);
      }
    }
    if (features.isEmpty) {
      await Future.wait(joining);
      return;
    }
    internalCacheLifecycle.invalidateReads();
    final lifecycleEpoch = internalLifecycleEpoch;
    final generations = <FeatureId, int>{
      for (final feature in features) feature: ++internalReadRequestRevision,
    };
    final ygdkGeneration =
        features.contains(FeatureId.ygdk) &&
            internalSnapshots[FeatureId.ygdk]?.readContext?.query == null
        ? ++internalYgdkGeneration
        : null;
    for (final feature in features) {
      final generation = generations[feature]!;
      internalBeginBusinessAttempt(feature, null, generation);
      if (internalSnapshots[feature]?.readContext?.query != null) {
        internalBeginHomeDefault(
          feature,
          FeatureReadContext(requestRevision: generation),
        );
      } else {
        internalFeatureRefreshGenerations[feature] = generation;
        internalBeginFeatureRead(feature, generation, null);
      }
    }
    internalNotify();
    await Future.wait([
      ...joining,
      ...features.map(
        (feature) => internalLoadFeature(
          feature,
          generations[feature]!,
          lifecycleEpoch,
          writeReadback: writeReadback,
          ygdkGeneration: feature == FeatureId.ygdk ? ygdkGeneration : null,
        ),
      ),
    ]);
  }

  @internal
  /// 对支持 [FeatureQueryBackend] 的生产实现执行单领域筛选读取。
  ///
  /// 不支持查询的 fake backend 明确报 unsupported，不会在 Dart 端拼接请求。
  Future<void> internalRefreshFeatureQuery(
    FeatureId feature,
    FeatureQuery query, {
    bool writeReadback = false,
  }) async {
    if (internalDisposed || internalClearingBusinessCache) return;
    if (!writeReadback) {
      final pending = internalPendingFeatureRead(feature, query);
      if (pending != null) {
        await pending;
        return;
      }
    }
    internalCancelSegmentedReadScopes(feature);
    // 换学期/视图可复用完整集合；同查询表示明确刷新，继续执行原读取。
    final cachedGrades =
        feature == FeatureId.grades &&
            internalSnapshots[feature]!.readContext?.hasSameQuery(query) != true
        ? internalCachedGradeQuery(query)
        : null;
    final generation = internalNextFeatureGeneration(feature);
    internalBeginBusinessAttempt(feature, query, generation);
    final context = internalBeginFeatureRead(feature, generation, query);
    if (internalBackend is! FeatureQueryBackend) {
      internalSnapshots[feature] = internalSnapshots[feature]!.copyWith(
        status: FeatureLoadStatus.failure,
        error: UbaaErrorMapper.fromCode(UbaaErrorCode.unsupported),
      );
      internalNotify();
      return;
    }
    final lifecycleEpoch = internalLifecycleEpoch;
    final ygdkGeneration = feature == FeatureId.ygdk
        ? ++internalYgdkGeneration
        : null;
    internalNotify();
    await internalLoadFeature(
      feature,
      generation,
      lifecycleEpoch,
      query: context.query,
      writeReadback: writeReadback,
      cachedResult: cachedGrades,
      ygdkGeneration: ygdkGeneration,
    );
  }

  @internal
  FeatureReadContext internalBeginFeatureRead(
    FeatureId feature,
    int generation,
    FeatureQuery? query,
  ) {
    final context = FeatureReadContext(
      query: query,
      requestRevision: generation,
    );
    final previous = internalSnapshots[feature]!;
    if (query == null) internalBeginHomeDefault(feature, context);
    internalSnapshots[feature] =
        previous.readContext?.hasSameQuery(query) == true
        ? previous.copyWith(
            status: FeatureLoadStatus.loading,
            clearError: true,
            readContext: context,
          )
        : FeatureSnapshot(
            feature: feature,
            status: FeatureLoadStatus.loading,
            readContext: context,
          );
    return context;
  }

  @internal
  int internalNextFeatureGeneration(FeatureId feature) {
    final next = ++internalReadRequestRevision;
    internalFeatureRefreshGenerations[feature] = next;
    return next;
  }

  @internal
  Future<void> internalLoadFeature(
    FeatureId feature,
    int generation,
    int lifecycleEpoch, {
    FeatureQuery? query,
    int? ygdkGeneration,
    FeatureResult? cachedResult,
    bool writeReadback = false,
  }) async {
    // loading 通知可能同步触发注销或切换路线，发请求前再次核对归属。
    if (!internalIsFeatureLoadCurrent(
          feature,
          generation,
          lifecycleEpoch,
          ygdkGeneration,
        ) &&
        !(query == null &&
            internalIsHomeDefaultCurrent(
              feature,
              generation,
              lifecycleEpoch,
            ))) {
      return;
    }
    final scope = ProgressiveScope(
      feature,
      query,
      () =>
          internalIsFeatureLoadCurrent(
            feature,
            generation,
            lifecycleEpoch,
            ygdkGeneration,
          ) ||
          (query == null &&
              internalIsHomeDefaultCurrent(
                feature,
                generation,
                lifecycleEpoch,
              )),
    );
    internalReadScopes.add(scope);
    if (query != null && !writeReadback) {
      unawaited(
        internalRestoreCachedQuery(
          feature,
          query,
          generation,
          lifecycleEpoch,
          ygdkGeneration,
        ),
      );
    }
    final started = DateTime.now();
    var completed = false;
    UiError? outcome;
    final previous = internalSnapshots[feature]!;
    final hadPreviousData =
        previous.updatedAt != null &&
        (previous.overview != null ||
            previous.details.isNotEmpty ||
            previous.summary?.trim().isNotEmpty == true ||
            previous.evidence != null);
    try {
      if (internalUsesLocalRecovery &&
          !writeReadback &&
          internalBackend is! ProgressiveReadBackend) {
        if (query != null && internalBackend is RequiredSessionBackend) {
          await internalRecoverSession(
            feature: feature,
            refreshHomeAfter: false,
          );
          if (internalDisposed || lifecycleEpoch != internalLifecycleEpoch)
            return;
          final status = recoveryStatusFor(feature);
          if (status != SessionRecoveryStatus.ready) {
            if (internalFeatureRecoveryErrors[feature] case final error?)
              throw BackendException.fromUi(error);
            throw BackendException(
              status == SessionRecoveryStatus.unavailable
                  ? UbaaErrorCode.networkError
                  : UbaaErrorCode.authenticationRequired,
            );
          }
        } else {
          await internalRequireReadSession(feature: feature);
        }
        if (internalDisposed || lifecycleEpoch != internalLifecycleEpoch)
          return;
      }
      final rawResult =
          cachedResult ??
          await internalReadScheduledFeature(
            feature,
            query,
            scope,
            writeReadback: writeReadback,
            onBatch: (batch) {
              if (!scope.valid) return;
              final result = controllerRetainJudgePartial(
                feature,
                query == null
                    ? internalHomeDefaults[feature]!
                    : internalSnapshots[feature]!,
                batch.result,
                pending: true,
              );
              if (query == null &&
                  internalIsHomeDefaultCurrent(
                    feature,
                    generation,
                    lifecycleEpoch,
                  )) {
                internalAcceptHomeDefault(
                  feature,
                  result,
                  FeatureReadContext(requestRevision: generation),
                );
                internalHomeDefaults[feature] = internalHomeDefaults[feature]!
                    .copyWith(status: FeatureLoadStatus.loading);
              }
              if (internalApplyFeatureResultIfCurrent(
                feature,
                result,
                generation,
                lifecycleEpoch,
                ygdkGeneration: ygdkGeneration,
                preservePreviousOnFailure: hadPreviousData,
              )) {
                internalSnapshots[feature] = internalSnapshots[feature]!
                    .copyWith(status: FeatureLoadStatus.loading);
              }
              internalNotify();
            },
          );
      final result = controllerRetainJudgePartial(
        feature,
        query == null
            ? internalHomeDefaults[feature]!
            : internalSnapshots[feature]!,
        rawResult,
      );
      completed = true;
      outcome = result.error;
      if (query == null &&
          internalIsHomeDefaultCurrent(feature, generation, lifecycleEpoch)) {
        internalAcceptHomeDefault(
          feature,
          result,
          FeatureReadContext(requestRevision: generation),
        );
      }
      if (!internalApplyFeatureResultIfCurrent(
        feature,
        result,
        generation,
        lifecycleEpoch,
        ygdkGeneration: ygdkGeneration,
        preservePreviousOnFailure: hadPreviousData,
      )) {
        internalNotify();
        return;
      }
      if (feature == FeatureId.grades) {
        internalRememberGradeResult(result, query, fresh: cachedResult == null);
      }
      await internalRecordFeature(
        feature,
        success:
            result.error == null &&
            !result.isEmpty &&
            result.evidence?.complete != false,
        empty: result.isEmpty && result.evidence?.complete != false,
        error: internalSnapshots[feature]!.error,
        latency: DateTime.now().difference(started),
      );
    } on Object catch (error, stackTrace) {
      if (error is ReadCancelled) return;
      final featureCurrent = internalIsFeatureLoadCurrent(
        feature,
        generation,
        lifecycleEpoch,
        ygdkGeneration,
      );
      final homeCurrent =
          query == null &&
          internalIsHomeDefaultCurrent(feature, generation, lifecycleEpoch);
      if (!featureCurrent && !homeCurrent) return;
      if (error is BackendException && error.accountMismatch) {
        await internalRejectMismatchedAccount();
        return;
      }
      final uiError = internalRecordFailure(
        error,
        DiagnosticOperation.read,
        stackTrace: stackTrace,
        feature: feature,
        latency: DateTime.now().difference(started),
      );
      completed = true;
      outcome = uiError;
      if (homeCurrent)
        internalAcceptHomeDefault(
          feature,
          FeatureResult.failure(uiError),
          FeatureReadContext(requestRevision: generation),
        );
      if (featureCurrent)
        internalSnapshots[feature] = internalSnapshots[feature]!.copyWith(
          status:
              (hadPreviousData || internalSnapshots[feature]!.evidence != null)
              ? FeatureLoadStatus.stale
              : FeatureLoadStatus.failure,
          error: uiError,
        );
      if (featureCurrent && feature == FeatureId.grades) {
        internalRememberGradeResult(FeatureResult.failure(uiError), query);
      }
      await internalRecordFeature(
        feature,
        error: uiError,
        latency: DateTime.now().difference(started),
      );
    } finally {
      if (completed && scope.valid && !writeReadback) {
        internalFinishBusinessAttempt(
          feature,
          query,
          generation,
          lifecycleEpoch,
          outcome,
        );
      }
      scope.cancel();
      internalReadScopes.remove(scope);
      if (!scope.completion.isCompleted) scope.completion.complete();
      internalSyncRecoveryRetries();
    }
    internalNotify();
  }

  @internal
  bool internalApplyFeatureResultIfCurrent(
    FeatureId feature,
    FeatureResult result,
    int generation,
    int lifecycleEpoch, {
    int? ygdkGeneration,
    FeatureReadContext? readContext,
    bool preservePreviousOnFailure = false,
  }) {
    if (!internalIsFeatureLoadCurrent(
      feature,
      generation,
      lifecycleEpoch,
      ygdkGeneration,
    )) {
      return false;
    }
    // 已保存的只读内容不因读取失败消失；身份不符由独立边界清空。
    if (result.error != null &&
        result.evidence == null &&
        result.details.isEmpty &&
        result.overview == null &&
        ((internalSnapshots[feature]!.evidence != null) ||
            (preservePreviousOnFailure &&
                (result.error?.code == UbaaErrorCode.networkError ||
                    result.error?.code == UbaaErrorCode.timeout ||
                    result.error?.code ==
                        UbaaErrorCode.upstreamUnavailable)))) {
      internalSnapshots[feature] = internalSnapshots[feature]!.copyWith(
        status: FeatureLoadStatus.stale,
        error: internalRecordFailure(
          result.error!,
          DiagnosticOperation.read,
          feature: feature,
        ),
      );
      return true;
    }
    final status = result.error != null
        ? (result.evidence != null ||
                  result.details.isNotEmpty ||
                  result.overview != null
              ? FeatureLoadStatus.stale
              : FeatureLoadStatus.failure)
        : result.evidence?.complete == false
        ? FeatureLoadStatus.stale
        : result.isEmpty
        ? FeatureLoadStatus.empty
        : FeatureLoadStatus.success;
    internalSnapshots[feature] = internalSnapshots[feature]!.copyWith(
      status: status,
      readContext:
          readContext ??
          internalSnapshots[feature]!.readContext ??
          FeatureReadContext(requestRevision: generation),
      overview: result.overview,
      clearOverview: result.overview == null,
      summary: result.summary,
      details: result.details,
      error: result.error == null
          ? null
          : internalRecordFailure(
              result.error!,
              DiagnosticOperation.read,
              feature: feature,
            ),
      resolvedRoute: result.resolvedRoute,
      pagination: result.pagination,
      updatedAt: result.evidence?.fetchedAt ?? DateTime.now(),
      evidence: result.evidence,
      clearEvidence: result.evidence == null,
      clearError: result.error == null,
      clearSummary: result.summary == null,
      clearDetails: result.details.isEmpty,
      clearResolvedRoute: result.resolvedRoute == null,
      clearPagination: result.pagination == null,
    );
    return true;
  }

  @internal
  bool internalIsFeatureLoadCurrent(
    FeatureId feature,
    int generation,
    int lifecycleEpoch,
    int? ygdkGeneration,
  ) =>
      !internalDisposed &&
      lifecycleEpoch == internalLifecycleEpoch &&
      generation == internalFeatureRefreshGenerations[feature] &&
      (feature != FeatureId.ygdk || ygdkGeneration == internalYgdkGeneration);

  @internal
  void internalResetFeatureSnapshots({bool advanceLifecycle = true}) {
    internalClearWriteReadbacks();
    internalProfileDisplay = null;
    internalProfileFailureEpoch = -1;
    internalFeatureRecoveryStates.clear();
    internalFeatureRecoveryErrors.clear();
    internalRecoveredRoute = null;
    internalCacheLifecycle.invalidateReads();
    if (advanceLifecycle) internalSessionLifecycle.invalidate();
    internalYgdkGeneration++;
    internalWriteCoordinator.invalidate();
    internalYgdkReadbackState = const YgdkReadbackState.empty();
    for (final feature in FeatureId.values) {
      internalSnapshots[feature] = FeatureSnapshot(feature: feature);
      internalHomeDefaults[feature] = FeatureSnapshot(feature: feature);
    }
  }
}

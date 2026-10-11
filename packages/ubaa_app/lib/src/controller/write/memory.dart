import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/write.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../state/models.dart' show WriteRefreshRequest;
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase;

mixin ControllerWriteCache on ControllerState {
  @internal
  Future<WriteCommitResult> internalCommitWithAccountCache(
    CacheWriteBackend backend,
    String intentId,
    String accountId,
  ) async {
    final epoch = internalLifecycleEpoch;
    final intent = internalWriteCoordinator.intent;
    bool current() =>
        !internalDisposed &&
        !internalIsSigningOut &&
        internalPhase == AppPhase.home &&
        identical(backend, internalBackend) &&
        epoch == internalLifecycleEpoch &&
        internalLocalAccount?.id == accountId;
    void warning(CacheMaintenanceFailure? failure) {
      if (failure != null && current())
        internalLocalCacheError = UbaaErrorMapper.fromCode(
          UbaaErrorCode.internalError,
        );
    }

    try {
      final result = await backend.commitWriteWithCache(
        intentId,
        accountId: accountId,
      );
      warning(result.cacheFailure);
      final changed =
          result.success ||
          result.outcomeUnknown ||
          (result.evaluationResult?.items.any(
                (item) =>
                    item.outcome == EvaluationCourseOutcome.success ||
                    item.outcome == EvaluationCourseOutcome.outcomeUnknown,
              ) ??
              false);
      if (changed && current()) {
        internalInvalidateWriteProjections(
          result.operation,
          result.resolvedRoute ?? intent?.resolvedRoute,
          current,
        );
      }
      return result;
    } on BackendException catch (error) {
      warning(error.cacheFailure);
      if (current() &&
          error.code == UbaaErrorCode.outcomeUnknown &&
          intent?.intentId == intentId) {
        internalInvalidateWriteProjections(
          intent!.operation,
          error.resolvedRoute ?? intent.resolvedRoute,
          current,
        );
      }
      rethrow;
    } finally {
      if (current()) unawaited(internalLoadWriteReadbacks(force: true));
    }
  }

  @internal
  void internalInvalidateWriteProjections(
    WriteOperation operation,
    ConnectionMode? route,
    bool Function() current,
  ) {
    final feature = switch (operation) {
      WriteOperation.bykcSelectCourse ||
      WriteOperation.bykcDeselectCourse ||
      WriteOperation.bykcSignCourse => FeatureId.bykc,
      WriteOperation.signinPerform => FeatureId.signin,
      WriteOperation.libbookReserve ||
      WriteOperation.libbookCancelBooking => FeatureId.libbook,
      WriteOperation.cgyySubmitReservation ||
      WriteOperation.cgyyCancelOrder => FeatureId.cgyy,
      WriteOperation.ygdkSubmit => FeatureId.ygdk,
      WriteOperation.evaluationSubmitCourses => FeatureId.evaluation,
    };
    // 只清返回帧的旧副本与关联领域的旧动作，业务数据不按全库清除。
    internalCacheLifecycle.invalidateReads();
    final generation = ++internalReadRequestRevision;
    internalFeatureRefreshGenerations[feature] = generation;
    if (feature == FeatureId.ygdk) internalYgdkGeneration++;
    for (final scope
        in internalReadScopes
            .where((scope) => scope.feature == feature)
            .toList()) {
      scope.cancel();
    }
    for (final values in [internalSnapshots, internalHomeDefaults]) {
      final old = values[feature]!;
      final context = FeatureReadContext(
        query: old.readContext?.query,
        requestRevision: generation,
      );
      if (route != null &&
          old.resolvedRoute != null &&
          old.resolvedRoute != route) {
        values[feature] = old.copyWith(readContext: context);
        continue;
      }
      final hasContent =
          old.details.isNotEmpty ||
          old.overview != null ||
          old.evidence != null;
      values[feature] = old.copyWith(
        status: hasContent ? FeatureLoadStatus.stale : FeatureLoadStatus.idle,
        details: readonlyFeatureDetails(old.details),
        overview: readonlyFeatureOverview(old.overview),
        readContext: context,
        error: hasContent
            ? const UiError(
                code: UbaaErrorCode.operationConflict,
                title: '相关内容待更新',
                message: '学校状态可能已变化，正在重新核对相关内容。',
                retryable: true,
                actionLabel: '刷新',
              )
            : null,
      );
    }
    internalWriteRefreshes[feature] = WriteRefreshRequest(current);
  }

  @internal
  bool get internalCanRefreshAfterWrite =>
      !internalDisposed &&
      !internalIsSigningOut &&
      internalPhase == AppPhase.home &&
      internalAppForeground &&
      !isLoggingIn &&
      !internalClearingBusinessCache &&
      !internalRebuildingBackend &&
      internalWriteTransitions == 0 &&
      !internalWriteCoordinator.hasPendingOperation &&
      internalActiveRecovery == null;

  @internal
  void internalDrainWriteRefreshes() {
    internalWriteRefreshes.removeWhere((_, value) => !value.current());
    if (internalWriteRefreshes.isEmpty ||
        internalWriteRefreshScheduled ||
        !internalCanRefreshAfterWrite)
      return;
    internalWriteRefreshScheduled = true;
    scheduleMicrotask(() {
      internalWriteRefreshScheduled = false;
      if (!internalCanRefreshAfterWrite) return;
      final pending = Map.of(internalWriteRefreshes);
      internalWriteRefreshes.clear();
      for (final entry in pending.entries) {
        if (!entry.value.current()) continue;
        unawaited(internalRefreshWrittenFeature(entry.key, entry.value));
      }
    });
  }

  @internal
  Future<void> internalRefreshWrittenFeature(
    FeatureId feature,
    WriteRefreshRequest request,
  ) async {
    if (!request.current()) return;
    final query = internalSnapshots[feature]!.readContext?.query;
    if (query == null) {
      await internalRefreshHome(only: [feature]);
    } else {
      await internalRefreshFeatureQuery(feature, query);
    }
    if (!request.current()) return;
    final source = switch (feature) {
      FeatureId.bykc => HomeSupplement.bykcChosen,
      FeatureId.cgyy => HomeSupplement.cgyyOrders,
      _ => null,
    };
    if (source != null)
      await internalLoadHomeSupplement(source, forceRefresh: true);
  }
}

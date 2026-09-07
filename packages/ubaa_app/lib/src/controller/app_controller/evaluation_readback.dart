part of '../app_controller.dart';

String? _trimEvaluationOptional(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

EvaluationSubmitTarget _normalizeEvaluationTarget(
  EvaluationSubmitTarget target,
) => EvaluationSubmitTarget(
  rwid: target.rwid.trim(),
  wjid: target.wjid.trim(),
  kcdm: target.kcdm.trim(),
  bpdm: _trimEvaluationOptional(target.bpdm),
);

/// 评教写后在 intent 原路线执行一次 best-effort 刷新。
Future<void> _refreshEvaluationAfterWrite(
  AppController controller, {
  required ConnectionMode expectedRoute,
}) async {
  if (controller._disposed ||
      controller._backend is! EvaluationSubmissionReadbackBackend) {
    return;
  }
  final backend = controller._backend as EvaluationSubmissionReadbackBackend;
  final lifecycleEpoch = controller._lifecycleEpoch;
  final generation = controller._nextFeatureGeneration(FeatureId.evaluation);
  controller._readCacheEpoch++;
  controller._beginFeatureRead(
    FeatureId.evaluation,
    generation,
    const FeatureQuery(view: FeatureQueryView.summary),
  );
  controller._notify();

  if (!controller._isFeatureLoadCurrent(
    FeatureId.evaluation,
    generation,
    lifecycleEpoch,
    null,
  )) {
    return;
  }
  try {
    final result = await backend.loadEvaluationOnRoute(route: expectedRoute);
    if (result.resolvedRoute != expectedRoute) {
      _setEvaluationReadbackFailureIfCurrent(
        controller,
        generation: generation,
        lifecycleEpoch: lifecycleEpoch,
        error: UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict),
      );
      return;
    }
    if (controller._applyFeatureResultIfCurrent(
      FeatureId.evaluation,
      result,
      generation,
      lifecycleEpoch,
    )) {
      controller._notify();
    }
  } on Object catch (error, stackTrace) {
    _setEvaluationReadbackFailureIfCurrent(
      controller,
      generation: generation,
      lifecycleEpoch: lifecycleEpoch,
      error: UbaaErrorMapper.fromObject(error),
      cause: error,
      stackTrace: stackTrace,
    );
  }
}

void _setEvaluationReadbackFailureIfCurrent(
  AppController controller, {
  required int generation,
  required int lifecycleEpoch,
  required UiError error,
  Object? cause,
  StackTrace? stackTrace,
}) {
  if (!controller._isFeatureLoadCurrent(
    FeatureId.evaluation,
    generation,
    lifecycleEpoch,
    null,
  )) {
    return;
  }
  controller._snapshots[FeatureId.evaluation] = FeatureSnapshot(
    feature: FeatureId.evaluation,
    status: FeatureLoadStatus.failure,
    readContext: FeatureReadContext(
      query: const FeatureQuery(view: FeatureQueryView.summary),
      requestRevision: generation,
    ),
    error: controller._recordFailure(
      cause ?? error,
      DiagnosticOperation.readback,
      stackTrace: stackTrace,
      feature: FeatureId.evaluation,
    ),
    updatedAt: DateTime.now(),
  );
  controller._notify();
}

import 'dart:async';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../state/state.dart' show ControllerState;

String? controllerTrimEvaluationOptional(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

EvaluationSubmitTarget controllerNormalizeEvaluationTarget(
  EvaluationSubmitTarget target,
) => EvaluationSubmitTarget(
  rwid: target.rwid.trim(),
  wjid: target.wjid.trim(),
  kcdm: target.kcdm.trim(),
  bpdm: controllerTrimEvaluationOptional(target.bpdm),
);

/// 评教写后在 intent 原路线执行一次 best-effort 刷新。
Future<void> controllerRefreshEvaluationAfterWrite(
  ControllerState controller, {
  required ConnectionMode expectedRoute,
}) async {
  if (controller.internalDisposed ||
      controller.internalBackend is! EvaluationSubmissionReadbackBackend) {
    return;
  }
  final backend =
      controller.internalBackend as EvaluationSubmissionReadbackBackend;
  final lifecycleEpoch = controller.internalLifecycleEpoch;
  final generation = controller.internalNextFeatureGeneration(
    FeatureId.evaluation,
  );
  controller.internalCacheLifecycle.invalidateReads();
  controller.internalBeginFeatureRead(
    FeatureId.evaluation,
    generation,
    const FeatureQuery(view: FeatureQueryView.summary),
  );
  controller.internalNotify();

  if (!controller.internalIsFeatureLoadCurrent(
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
      controllerSetEvaluationReadbackFailureIfCurrent(
        controller,
        generation: generation,
        lifecycleEpoch: lifecycleEpoch,
        error: UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict),
      );
      return;
    }
    if (controller.internalApplyFeatureResultIfCurrent(
      FeatureId.evaluation,
      result,
      generation,
      lifecycleEpoch,
    )) {
      controller.internalNotify();
    }
  } on Object catch (error, stackTrace) {
    controllerSetEvaluationReadbackFailureIfCurrent(
      controller,
      generation: generation,
      lifecycleEpoch: lifecycleEpoch,
      error: UbaaErrorMapper.fromObject(error),
      cause: error,
      stackTrace: stackTrace,
    );
  }
}

void controllerSetEvaluationReadbackFailureIfCurrent(
  ControllerState controller, {
  required int generation,
  required int lifecycleEpoch,
  required UiError error,
  Object? cause,
  StackTrace? stackTrace,
}) {
  if (!controller.internalIsFeatureLoadCurrent(
    FeatureId.evaluation,
    generation,
    lifecycleEpoch,
    null,
  )) {
    return;
  }
  controller.internalSnapshots[FeatureId.evaluation] = FeatureSnapshot(
    feature: FeatureId.evaluation,
    status: FeatureLoadStatus.failure,
    readContext: FeatureReadContext(
      query: const FeatureQuery(view: FeatureQueryView.summary),
      requestRevision: generation,
    ),
    error: controller.internalRecordFailure(
      cause ?? error,
      DiagnosticOperation.readback,
      stackTrace: stackTrace,
      feature: FeatureId.evaluation,
    ),
    updatedAt: DateTime.now(),
  );
  controller.internalNotify();
}

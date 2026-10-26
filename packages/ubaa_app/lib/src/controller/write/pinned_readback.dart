import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import '../state/state.dart';

/// 固定原路线并复用统一快照回写；不重试提交、不改变全局路线偏好。
Future<void> controllerPinnedWriteReadback(
  ControllerState controller,
  WriteOperation operation,
  FeatureQuery? query,
  ConnectionMode route,
) async {
  final backend = controller.internalBackend;
  if (backend is! PinnedWriteReadbackBackend) return;
  final feature = switch (operation) {
    WriteOperation.bykcSelectCourse ||
    WriteOperation.bykcDeselectCourse ||
    WriteOperation.bykcSignCourse => FeatureId.bykc,
    WriteOperation.signinPerform => FeatureId.signin,
    WriteOperation.libbookReserve ||
    WriteOperation.libbookCancelBooking => FeatureId.libbook,
    WriteOperation.cgyySubmitReservation => FeatureId.cgyy,
    _ => throw const BackendException(UbaaErrorCode.invalidInput),
  };
  final readQuery = switch (feature) {
    FeatureId.bykc => const FeatureQuery(
      view: FeatureQueryView.bykcChosenCourses,
    ),
    FeatureId.libbook =>
      query ?? const FeatureQuery(view: FeatureQueryView.libbookBookings),
    FeatureId.cgyy => const FeatureQuery(view: FeatureQueryView.cgyyOrders),
    _ => const FeatureQuery(),
  };
  final scope = controller.internalCaptureSessionScope();
  final generation = controller.internalNextFeatureGeneration(feature);
  controller.internalCacheLifecycle.invalidateReads();
  final context = controller.internalBeginFeatureRead(
    feature,
    generation,
    readQuery,
  );
  if (feature == FeatureId.signin)
    controller.internalBeginHomeDefault(feature, context);
  controller.internalNotify();
  if (!scope.isCurrent) return;
  try {
    final result = await (backend as PinnedWriteReadbackBackend)
        .readAfterWriteOnRoute(operation, route: route, query: readQuery);
    if (!scope.isCurrent) return;
    if (result.resolvedRoute != route)
      throw const BackendException(UbaaErrorCode.operationConflict);
    if (controller.internalApplyFeatureResultIfCurrent(
      feature,
      result,
      generation,
      scope.lifecycle,
    )) {
      if (feature == FeatureId.signin)
        controller.internalAcceptHomeDefault(feature, result, context);
      controller.internalNotify();
    }
  } on Object catch (error, stackTrace) {
    if (!scope.isCurrent ||
        !controller.internalIsFeatureLoadCurrent(
          feature,
          generation,
          scope.lifecycle,
          null,
        ))
      return;
    controller.internalSnapshots[feature] = FeatureSnapshot(
      feature: feature,
      status: FeatureLoadStatus.failure,
      readContext: FeatureReadContext(
        query: readQuery,
        requestRevision: generation,
      ),
      error: controller.internalRecordFailure(
        error,
        DiagnosticOperation.readback,
        stackTrace: stackTrace,
        feature: feature,
      ),
      updatedAt: DateTime.now(),
    );
    if (feature == FeatureId.signin) {
      controller.internalAcceptHomeDefault(
        feature,
        FeatureResult.failure(controller.internalSnapshots[feature]!.error!),
        context,
      );
    }
    controller.internalNotify();
  }
}

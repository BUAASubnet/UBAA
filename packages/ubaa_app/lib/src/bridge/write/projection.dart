import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/backend.dart';
import '../features/evaluation/projection.dart'
    show bridgeMapEvaluationSubmitTarget;
import '../support/mapping.dart' show bridgeToConnectionMode;

BackendException bridgeWriteCacheError(
  BackendException error,
  CacheMaintenanceFailure? failure,
) => BackendException(
  error.code,
  detail: error.detail,
  kind: error.kind,
  retryable: error.retryable,
  resolvedRoute: error.resolvedRoute,
  issueId: error.issueId,
  accountMismatch: error.accountMismatch,
  cacheFailure: failure ?? error.cacheFailure,
);

EvaluationBatchResult bridgeMapEvaluationBatchResult(
  BridgeEvaluationBatchResult? batch,
) {
  if (batch == null || batch.items.isEmpty) {
    throw const BackendException(UbaaErrorCode.outcomeUnknown);
  }
  final targetKeys = <String>{};
  final items = <EvaluationCourseResult>[];
  var sawUnknown = false;
  for (final item in batch.items) {
    final target = bridgeMapEvaluationSubmitTarget(item.target);
    if (target == null || !targetKeys.add(target.selectionKey)) {
      throw const BackendException(UbaaErrorCode.outcomeUnknown);
    }
    final outcome = switch (item.outcome) {
      BridgeEvaluationCourseOutcome.success => EvaluationCourseOutcome.success,
      BridgeEvaluationCourseOutcome.failure => EvaluationCourseOutcome.failure,
      BridgeEvaluationCourseOutcome.outcomeUnknown =>
        EvaluationCourseOutcome.outcomeUnknown,
      BridgeEvaluationCourseOutcome.unattempted =>
        EvaluationCourseOutcome.unattempted,
    };
    if ((sawUnknown && outcome != EvaluationCourseOutcome.unattempted) ||
        (!sawUnknown && outcome == EvaluationCourseOutcome.unattempted)) {
      throw const BackendException(UbaaErrorCode.outcomeUnknown);
    }
    if (outcome == EvaluationCourseOutcome.outcomeUnknown) sawUnknown = true;
    items.add(
      EvaluationCourseResult(
        target: target,
        courseName: item.courseName.trim().isEmpty ? '教学评教课程' : item.courseName,
        outcome: outcome,
        message: switch (outcome) {
          EvaluationCourseOutcome.success => '评教提交成功',
          EvaluationCourseOutcome.failure => '评教提交失败',
          EvaluationCourseOutcome.outcomeUnknown => '评教提交结果无法确认',
          EvaluationCourseOutcome.unattempted => '未尝试提交',
        },
      ),
    );
  }
  final success = items.every(
    (item) => item.outcome == EvaluationCourseOutcome.success,
  );
  final outcomeUnknown = items.any(
    (item) => item.outcome == EvaluationCourseOutcome.outcomeUnknown,
  );
  if (batch.success != success || batch.outcomeUnknown != outcomeUnknown) {
    throw const BackendException(UbaaErrorCode.outcomeUnknown);
  }
  return EvaluationBatchResult(
    items: List<EvaluationCourseResult>.unmodifiable(items),
    success: success,
    outcomeUnknown: outcomeUnknown,
  );
}

WriteIntent bridgeMapIntent(BridgeWriteIntent intent) => WriteIntent(
  intentId: intent.intentId,
  operation: bridgeToWriteOperation(intent.operation),
  targetSummary: intent.targetSummary,
  resolvedRoute: bridgeToConnectionMode(intent.resolvedRoute),
  warnings: List<String>.unmodifiable(intent.warnings),
  expiresAt: DateTime.fromMillisecondsSinceEpoch(
    int.parse(intent.expiresAt.toString()) * 1000,
  ),
  requestDigest: intent.requestDigest,
);

CgyyReservationReceipt? bridgeMapCgyyReceipt(
  BridgeCgyyReservationReceipt? receipt,
) {
  if (receipt == null || receipt.orderId <= 0) return null;
  return CgyyReservationReceipt(
    orderId: receipt.orderId,
    venueSiteId: receipt.venueSiteId,
    reservationDate: receipt.reservationDate?.trim().isEmpty ?? true
        ? null
        : receipt.reservationDate!.trim(),
    orderStatus: receipt.orderStatus,
  );
}

YgdkSubmitReceipt? bridgeMapYgdkReceipt(BridgeYgdkSubmitReceipt? receipt) {
  if (receipt == null || receipt.recordId <= 0) return null;
  return YgdkSubmitReceipt(recordId: receipt.recordId);
}

WriteOperation bridgeToWriteOperation(BridgeWriteOperation operation) =>
    switch (operation) {
      BridgeWriteOperation.bykcSelectCourse => WriteOperation.bykcSelectCourse,
      BridgeWriteOperation.bykcDeselectCourse =>
        WriteOperation.bykcDeselectCourse,
      BridgeWriteOperation.bykcSignCourse => WriteOperation.bykcSignCourse,
      BridgeWriteOperation.signinPerform => WriteOperation.signinPerform,
      BridgeWriteOperation.libbookReserve => WriteOperation.libbookReserve,
      BridgeWriteOperation.libbookCancelBooking =>
        WriteOperation.libbookCancelBooking,
      BridgeWriteOperation.ygdkSubmit => WriteOperation.ygdkSubmit,
      BridgeWriteOperation.cgyySubmitReservation =>
        WriteOperation.cgyySubmitReservation,
      BridgeWriteOperation.cgyyCancelOrder => WriteOperation.cgyyCancelOrder,
      BridgeWriteOperation.evaluationSubmitCourses =>
        WriteOperation.evaluationSubmitCourses,
    };

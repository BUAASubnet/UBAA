part of '../bridge_backend.dart';

Future<WriteCommitResult> _commitWrite(
  BridgeBackend backend,
  String intentId, {
  String? cacheAccountId,
}) async {
  // 写入结果不能由返回时的本地代次覆盖；仓库仅使用调用开始时的原账号句柄。
  final cache =
      cacheAccountId != null &&
          backend._offlineAccount?.id == cacheAccountId &&
          backend._offlineTargetAccountId == cacheAccountId
      ? backend._offlineCache
      : null;
  CacheMaintenanceFailure? cacheFailure =
      cacheAccountId != null && cache == null
      ? CacheMaintenanceFailure.unavailable
      : null;
  try {
    final BridgeWriteCommitResult result;
    if (cache != null) {
      final value = await backend.client.commitWriteCached(
        cache: cache,
        intentId: intentId,
      );
      cacheFailure = _cacheMaintenanceFailure(value.cacheError);
      if ((value.result == null) == (value.error == null)) {
        throw const BackendException(UbaaErrorCode.outcomeUnknown);
      }
      if (value.error case final error?) throw _mapError(error);
      result = value.result!;
    } else {
      result = await backend.client.commitWrite(intentId: intentId);
    }
    final operation = _toWriteOperation(result.operation);
    final evaluationResult = operation == WriteOperation.evaluationSubmitCourses
        ? _mapEvaluationBatchResult(result.evaluationResult)
        : null;
    if (evaluationResult != null &&
        (result.success != evaluationResult.success ||
            result.outcomeUnknown != evaluationResult.outcomeUnknown)) {
      throw const BackendException(UbaaErrorCode.outcomeUnknown);
    }
    return WriteCommitResult(
      operation: operation,
      success: result.success,
      message: evaluationResult == null
          ? result.message
          : evaluationResult.success
          ? '教学评教已全部提交'
          : evaluationResult.outcomeUnknown
          ? '教学评教提交结果无法确认，请刷新课程后核对'
          : '教学评教部分课程未提交，请刷新课程后重试',
      outcomeUnknown: result.outcomeUnknown,
      resolvedRoute: result.resolvedRoute == null
          ? null
          : _toConnectionMode(result.resolvedRoute!),
      cgyyReceipt:
          result.operation == BridgeWriteOperation.cgyySubmitReservation
          ? _mapCgyyReceipt(result.cgyyReceipt)
          : null,
      ygdkReceipt:
          result.operation == BridgeWriteOperation.ygdkSubmit &&
              result.success &&
              !result.outcomeUnknown
          ? _mapYgdkReceipt(result.ygdkReceipt)
          : null,
      evaluationResult: evaluationResult,
      cacheFailure: cacheFailure,
    );
  } on BridgeError catch (error) {
    throw _writeCacheError(_mapError(error), cacheFailure);
  } on BackendException catch (error) {
    throw _writeCacheError(error, cacheFailure);
  }
}

BackendException _writeCacheError(
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

EvaluationBatchResult _mapEvaluationBatchResult(
  BridgeEvaluationBatchResult? batch,
) {
  if (batch == null || batch.items.isEmpty) {
    throw const BackendException(UbaaErrorCode.outcomeUnknown);
  }
  final targetKeys = <String>{};
  final items = <EvaluationCourseResult>[];
  var sawUnknown = false;
  for (final item in batch.items) {
    final target = _mapEvaluationSubmitTarget(item.target);
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

WriteIntent _mapIntent(BridgeWriteIntent intent) => WriteIntent(
  intentId: intent.intentId,
  operation: _toWriteOperation(intent.operation),
  targetSummary: intent.targetSummary,
  resolvedRoute: _toConnectionMode(intent.resolvedRoute),
  warnings: List<String>.unmodifiable(intent.warnings),
  expiresAt: DateTime.fromMillisecondsSinceEpoch(
    int.parse(intent.expiresAt.toString()) * 1000,
  ),
  requestDigest: intent.requestDigest,
);

CgyyReservationReceipt? _mapCgyyReceipt(BridgeCgyyReservationReceipt? receipt) {
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

YgdkSubmitReceipt? _mapYgdkReceipt(BridgeYgdkSubmitReceipt? receipt) {
  if (receipt == null || receipt.recordId <= 0) return null;
  return YgdkSubmitReceipt(recordId: receipt.recordId);
}

WriteOperation _toWriteOperation(BridgeWriteOperation operation) =>
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

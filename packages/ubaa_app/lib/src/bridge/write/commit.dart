part of '../bridge_backend.dart';

Future<WriteCommitResult> _commitWrite(
  BridgeBackend backend,
  String intentId,
) async {
  try {
    final result = await backend.client.commitWrite(intentId: intentId);
    return WriteCommitResult(
      operation: _toWriteOperation(result.operation),
      success: result.success,
      message: result.message,
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
    );
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
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

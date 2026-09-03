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
          ? _mapCgyyReceipt(result.order)
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

CgyyReservationReceipt? _mapCgyyReceipt(BridgeCgyyOrder? order) {
  if (order == null || order.id <= 0) return null;
  return CgyyReservationReceipt(
    orderId: order.id,
    venueSiteId: order.venueSiteId,
    reservationDate: order.reservationDate?.trim().isEmpty ?? true
        ? null
        : order.reservationDate!.trim(),
    orderStatus: order.orderStatus,
  );
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

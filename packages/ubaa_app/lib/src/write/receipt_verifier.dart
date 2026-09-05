import 'package:ubaa_domain/ubaa_domain.dart';

/// 一次提交后的只读核对；不保存写状态，也不重试或升级提交结果。
class WriteReceiptVerifier {
  const WriteReceiptVerifier({
    this.refreshAfterWrite,
    this.verifyCgyyReceipt,
    this.verifyCgyyCancellation,
    this.refreshYgdkAfterWrite,
    this.refreshEvaluationAfterWrite,
  });

  final Future<void> Function(WriteOperation, FeatureQuery?)? refreshAfterWrite;
  final Future<bool> Function(CgyyReservationReceipt)? verifyCgyyReceipt;
  final Future<bool> Function({
    required int orderId,
    required ConnectionMode expectedRoute,
  })?
  verifyCgyyCancellation;
  final Future<void> Function({required ConnectionMode expectedRoute})?
  refreshYgdkAfterWrite;
  final Future<void> Function({required ConnectionMode expectedRoute})?
  refreshEvaluationAfterWrite;

  Future<WriteOutcome> complete(
    WriteIntent intent, {
    WriteCommitResult? result,
    UiError? error,
    required bool Function() isCurrent,
  }) async {
    assert((result == null) != (error == null));
    bool? receiptVerified;
    bool? cancellationVerified;
    var ygdkAttempted = false;
    final operation = intent.operation;
    final shouldRead = result != null
        ? result.success ||
              result.outcomeUnknown ||
              (operation == WriteOperation.evaluationSubmitCourses &&
                  result.evaluationResult != null)
        : error?.code == UbaaErrorCode.outcomeUnknown ||
              operation == WriteOperation.evaluationSubmitCourses;

    if (shouldRead && isCurrent()) {
      if (operation == WriteOperation.evaluationSubmitCourses) {
        await _refreshPinned(refreshEvaluationAfterWrite, intent.resolvedRoute);
      } else if (operation == WriteOperation.ygdkSubmit) {
        ygdkAttempted = refreshYgdkAfterWrite != null;
        await _refreshPinned(refreshYgdkAfterWrite, intent.resolvedRoute);
      } else if (operation == WriteOperation.cgyyCancelOrder) {
        cancellationVerified = await _verifyCancellation(intent);
      } else {
        try {
          await refreshAfterWrite?.call(operation, intent.readbackQuery);
        } on Object {
          // 读取失败不改变已经闭合的提交结果。
        }
      }
    }
    if (result != null &&
        result.success &&
        !result.outcomeUnknown &&
        operation == WriteOperation.cgyySubmitReservation &&
        isCurrent()) {
      final receipt = result.cgyyReceipt;
      if (receipt != null) {
        try {
          receiptVerified = await verifyCgyyReceipt?.call(receipt);
        } on Object {
          // 保留未核对状态，不重试提交。
        }
      }
    }
    return WriteOutcome(
      operation: operation,
      result: result,
      error: error,
      cgyyReceiptVerified: receiptVerified,
      cgyyCancellationVerified: cancellationVerified,
      ygdkReadbackAttempted: ygdkAttempted,
      message: result == null
          ? _errorMessage(
              error!,
              operation,
              cancellationVerified,
              ygdkAttempted,
            )
          : _resultMessage(
              result,
              receiptVerified,
              cancellationVerified,
              ygdkAttempted,
            ),
    );
  }

  Future<void> _refreshPinned(
    Future<void> Function({required ConnectionMode expectedRoute})? refresh,
    ConnectionMode route,
  ) async {
    try {
      await refresh?.call(expectedRoute: route);
    } on Object {
      // 仅记录读取尝试，不能从读取错误推断提交成功与否。
    }
  }

  Future<bool> _verifyCancellation(WriteIntent intent) async {
    final query = intent.readbackQuery;
    final orderId = query?.view == FeatureQueryView.cgyyOrderDetail
        ? query?.orderId
        : null;
    final verify = verifyCgyyCancellation;
    if (orderId == null || orderId <= 0 || verify == null) return false;
    try {
      return await verify(
        orderId: orderId,
        expectedRoute: intent.resolvedRoute,
      );
    } on Object {
      return false;
    }
  }

  String _unknownMessage(
    WriteOperation operation,
    bool? cancellationVerified,
    bool ygdkAttempted,
  ) {
    if (operation == WriteOperation.ygdkSubmit) {
      return ygdkAttempted
          ? '提交结果不确定；已尝试按原路线刷新概览与记录，请勿重复提交。'
          : '提交结果不确定；未能自动刷新概览与记录，请勿重复提交。';
    }
    return cancellationVerified == true
        ? '提交响应不确定，但场馆订单取消状态已核对，请勿重复提交。'
        : '提交结果不确定，请先刷新相关状态，不要重复提交。';
  }

  String _errorMessage(
    UiError error,
    WriteOperation operation,
    bool? cancellationVerified,
    bool ygdkAttempted,
  ) {
    if (error.code == UbaaErrorCode.outcomeUnknown) {
      return _unknownMessage(operation, cancellationVerified, ygdkAttempted);
    }
    if (operation == WriteOperation.ygdkSubmit &&
        error.code == UbaaErrorCode.upstreamUnavailable) {
      return '照片上传未完成，应用不会自动重试；本次阳光打卡尚未最终提交。';
    }
    if (error.code == UbaaErrorCode.internalError) {
      return '应用内部错误，请返回后刷新相关状态。';
    }
    return error.message;
  }

  String _resultMessage(
    WriteCommitResult result,
    bool? receiptVerified,
    bool? cancellationVerified,
    bool ygdkAttempted,
  ) {
    if (result.outcomeUnknown) {
      return _unknownMessage(
        result.operation,
        cancellationVerified,
        ygdkAttempted,
      );
    }
    if (result.operation == WriteOperation.cgyyCancelOrder) {
      final hint = cancellationVerified == true ? '取消状态已核对' : '取消状态尚未核对，请勿重复提交';
      return '${result.message}（$hint）';
    }
    if (result.operation == WriteOperation.ygdkSubmit) {
      if (!result.success) return result.message;
      final receipt = result.ygdkReceipt;
      final readbackHint = ygdkAttempted ? '已尝试按原路线刷新概览与记录' : '请手动刷新概览与记录';
      final hint = receipt?.isValid == true
          ? '记录编号 ${receipt!.recordId}；$readbackHint'
          : readbackHint;
      return '${result.message}（$hint）';
    }
    final receipt = result.cgyyReceipt;
    if (result.operation == WriteOperation.cgyySubmitReservation &&
        receipt != null) {
      final hint = receiptVerified == true ? '订单列表已核对' : '请在订单列表核对';
      return '${result.message}（订单编号 ${receipt.orderId}，$hint）';
    }
    return result.message;
  }
}

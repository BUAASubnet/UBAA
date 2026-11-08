import 'package:ubaa_domain/ubaa_domain.dart';

/// 一次提交后的只读核对；不保存写状态，也不重试或升级提交结果。
class WriteReceiptVerifier {
  const WriteReceiptVerifier({
    this.refreshAfterWrite,
    this.refreshPinnedAfterWrite,
    this.verifyCgyyReceipt,
    this.verifyCgyyCancellation,
    this.refreshYgdkAfterWrite,
    this.refreshEvaluationAfterWrite,
  });

  final Future<void> Function(WriteOperation, FeatureQuery?)? refreshAfterWrite;
  final Future<void> Function(WriteOperation, FeatureQuery?, ConnectionMode)?
  refreshPinnedAfterWrite;
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
    void Function(Object, StackTrace)? onReadbackError,
  }) async {
    assert((result == null) != (error == null));
    void report(Object cause, StackTrace stackTrace) {
      if (!isCurrent()) return;
      try {
        onReadbackError?.call(cause, stackTrace);
      } on Object {
        // 诊断失败不改变提交结果或原路线回读规则。
      }
    }

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
        await _refreshPinned(
          refreshEvaluationAfterWrite,
          intent.resolvedRoute,
          report,
        );
      } else if (operation == WriteOperation.ygdkSubmit) {
        ygdkAttempted = refreshYgdkAfterWrite != null;
        await _refreshPinned(
          refreshYgdkAfterWrite,
          intent.resolvedRoute,
          report,
        );
      } else if (operation == WriteOperation.cgyyCancelOrder) {
        cancellationVerified = await _verifyCancellation(intent, report);
      } else {
        try {
          final pinned = refreshPinnedAfterWrite;
          if (pinned != null) {
            await pinned(operation, intent.readbackQuery, intent.resolvedRoute);
          } else {
            await refreshAfterWrite?.call(operation, intent.readbackQuery);
          }
        } on Object catch (cause, stackTrace) {
          // 读取失败不改变已经闭合的提交结果。
          report(cause, stackTrace);
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
        } on Object catch (cause, stackTrace) {
          // 保留未核对状态，不重试提交。
          report(cause, stackTrace);
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
          ? _errorMessage(error!, operation, cancellationVerified)
          : _resultMessage(result, receiptVerified, cancellationVerified),
    );
  }

  Future<void> _refreshPinned(
    Future<void> Function({required ConnectionMode expectedRoute})? refresh,
    ConnectionMode route,
    void Function(Object, StackTrace) report,
  ) async {
    try {
      await refresh?.call(expectedRoute: route);
    } on Object catch (cause, stackTrace) {
      // 仅记录读取尝试，不能从读取错误推断提交成功与否。
      report(cause, stackTrace);
    }
  }

  Future<bool> _verifyCancellation(
    WriteIntent intent,
    void Function(Object, StackTrace) report,
  ) async {
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
    } on Object catch (cause, stackTrace) {
      report(cause, stackTrace);
      return false;
    }
  }

  /// 结果不明时只提示不要重复提交；已核对到取消状态时直接告知结果。
  String _unknownMessage(
    WriteOperation operation,
    bool? cancellationVerified,
  ) =>
      operation == WriteOperation.cgyyCancelOrder &&
          cancellationVerified == true
      ? '已取消预约'
      : '结果未确认，请刷新后查看，勿重复提交';

  String _errorMessage(
    UiError error,
    WriteOperation operation,
    bool? cancellationVerified,
  ) {
    if (error.code == UbaaErrorCode.outcomeUnknown) {
      return _unknownMessage(operation, cancellationVerified);
    }
    if (operation == WriteOperation.ygdkSubmit &&
        error.code == UbaaErrorCode.upstreamUnavailable) {
      return '照片上传失败，打卡未提交，请重试';
    }
    if (error.code == UbaaErrorCode.internalError) {
      return '操作失败，请刷新后重试';
    }
    return error.message;
  }

  String _resultMessage(
    WriteCommitResult result,
    bool? receiptVerified,
    bool? cancellationVerified,
  ) {
    if (result.outcomeUnknown) {
      return _unknownMessage(result.operation, cancellationVerified);
    }
    // 研讨室订单列表里查不到新订单时提醒用户自行确认，其余成功只给结论。
    if (result.operation == WriteOperation.cgyySubmitReservation &&
        result.success &&
        result.cgyyReceipt != null &&
        receiptVerified == false) {
      return '预约已提交，请在预约记录中确认';
    }
    return result.message;
  }
}

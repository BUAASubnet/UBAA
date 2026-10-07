import 'dart:async';
import 'dart:typed_data';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/write/cgyy_validation.dart';
import 'package:ubaa_app/src/write/ygdk_validation.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../cache/lifecycle.dart'
    show bridgeAwaitOfflineScope, bridgeManagementCache, bridgeWithOfflineRead;
import '../support/mapping.dart'
    show
        bridgeCacheMaintenanceFailure,
        bridgeCacheTime,
        bridgeMapError,
        bridgeToConnectionMode;
import 'projection.dart'
    show
        bridgeMapCgyyReceipt,
        bridgeMapEvaluationBatchResult,
        bridgeMapIntent,
        bridgeMapYgdkReceipt,
        bridgeToWriteOperation,
        bridgeWriteCacheError;
part 'readback.dart';
part 'lifecycle.dart';
part 'prepare.dart';

Future<WriteCommitResult> bridgeCommitWrite(
  BridgeContext backend,
  String intentId, {
  String? cacheAccountId,
}) async {
  // 写入结果不能由返回时的本地代次覆盖；仓库仅使用调用开始时的原账号句柄。
  final cache =
      cacheAccountId != null &&
          backend.cache.account?.id == cacheAccountId &&
          backend.cache.targetAccountId == cacheAccountId
      ? backend.cache.handle
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
      cacheFailure = bridgeCacheMaintenanceFailure(value.cacheError);
      if ((value.result == null) == (value.error == null)) {
        throw const BackendException(UbaaErrorCode.outcomeUnknown);
      }
      if (value.error case final error?) throw bridgeMapError(error);
      result = value.result!;
    } else {
      result = await backend.client.commitWrite(intentId: intentId);
    }
    final operation = bridgeToWriteOperation(result.operation);
    final evaluationResult = operation == WriteOperation.evaluationSubmitCourses
        ? bridgeMapEvaluationBatchResult(result.evaluationResult)
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
          : bridgeToConnectionMode(result.resolvedRoute!),
      cgyyReceipt:
          result.operation == BridgeWriteOperation.cgyySubmitReservation
          ? bridgeMapCgyyReceipt(result.cgyyReceipt)
          : null,
      ygdkReceipt:
          result.operation == BridgeWriteOperation.ygdkSubmit &&
              result.success &&
              !result.outcomeUnknown
          ? bridgeMapYgdkReceipt(result.ygdkReceipt)
          : null,
      evaluationResult: evaluationResult,
      cacheFailure: cacheFailure,
    );
  } on BridgeError catch (error) {
    throw bridgeWriteCacheError(bridgeMapError(error), cacheFailure);
  } on BackendException catch (error) {
    throw bridgeWriteCacheError(error, cacheFailure);
  }
}

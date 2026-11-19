import 'dart:async';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../contracts/backend.dart';
import '../../contracts/recovery.dart';
import '../../contracts/session_recovery.dart';
import '../error_mapper.dart';
import '../state/state.dart';
import '../state/activity.dart';

/// 专用服务复用所需路线恢复；业务读取最多重试一次，写入不进入本流程。
mixin ControllerServiceRecovery on ControllerState {
  @internal
  UiError internalRecordServiceFailure(
    Object error,
    DiagnosticOperation operation,
    StackTrace stack, {
    int? fileIndex,
    Duration? latency,
    String? relatedIssueId,
    int? recoveryAttempts,
  }) {
    if (error is UiError && error.issueId != null) return error;
    final recorded = internalRecordFailure(
      error,
      operation,
      stackTrace: stack,
      fileIndex: fileIndex,
      latency: latency,
      relatedIssueId: relatedIssueId,
      recoveryAttempts: recoveryAttempts,
    );
    // 专用服务已为界面生成过安全提示；保留提示和本地报告编号。
    return error is UiError && recorded.issueId != null
        ? error.withIssueId(recorded.issueId!)
        : recorded;
  }

  @internal
  void internalRecordServiceOutcome(
    DiagnosticOperation operation, {
    UiError? error,
    ConnectionMode? route,
    bool write = false,
  }) {
    if (operation.serviceFeature case final feature?) {
      internalRecordOperationOutcome(
        feature,
        write: write,
        error: error,
        route: route,
      );
    }
  }

  @internal
  Future<T> internalReadService<T>(
    RecoveryTarget target,
    DiagnosticOperation operation,
    Future<T> Function() read,
  ) async {
    final completion = Completer<void>();
    internalServiceReads.add(completion);
    try {
      while (true) {
        await internalAwaitNetworkReady();
        final network = internalNetworkRevision;
        try {
          final value = await _readServiceAttempt(
            target,
            operation,
            network,
            read,
          );
          if (network == internalNetworkRevision) return value;
        } on Object {
          if (network == internalNetworkRevision ||
              internalDisposed ||
              internalIsSigningOut)
            rethrow;
        }
      }
    } finally {
      internalServiceReads.remove(completion);
      completion.complete();
    }
  }

  Future<T> _readServiceAttempt<T>(
    RecoveryTarget target,
    DiagnosticOperation operation,
    int network,
    Future<T> Function() read,
  ) async {
    final elapsed = Stopwatch()..start();
    final session = internalCaptureSessionScope();
    final credentialRevision = internalLoginCredentialRevision;
    bool current() =>
        session.isCurrent &&
        network == internalNetworkRevision &&
        credentialRevision == internalLoginCredentialRevision;
    T? partial;
    Object? originalFailure;
    StackTrace? originalStack;
    Duration? originalLatency;
    var recoveryAttempts = 0;
    Future<T> checkedRead({bool recoverMetrics = false}) async {
      if (!current())
        throw const RecoveryInterrupted(RecoveryStopReason.superseded);
      final result = await read();
      if (!current())
        throw const RecoveryInterrupted(RecoveryStopReason.superseded);
      UiError? partFailure;
      if (result is CampusMetrics) {
        final failures = [
          result.networkBalance,
          result.cardBalance,
          result.unreadMail,
          result.borrowedBooks,
          result.cloudStorageRemaining,
        ].whereType<CampusMetricFailure<Object?>>();
        if (recoverMetrics) {
          for (final metric in failures) {
            if (metric.error?.code == UbaaErrorCode.authenticationRequired) {
              partial = result;
              throw metric.error!;
            }
          }
        }
        for (final metric in failures) {
          final error = internalRecordServiceFailure(
            metric.error ??
                UbaaErrorMapper.fromCode(UbaaErrorCode.internalError),
            operation,
            StackTrace.current,
          );
          partFailure ??= error;
        }
      }
      internalRecordServiceOutcome(
        operation,
        error: partFailure,
        route: switch (result) {
          IhomeResult<Object?>(:final route) ||
          BhpanPage(:final route) ||
          FinanceSnapshot(:final route) => route,
          _ => null,
        },
      );
      return result;
    }

    try {
      try {
        return await checkedRead(recoverMetrics: true);
      } on Object catch (error, stack) {
        final failure = UbaaErrorMapper.fromObject(error);
        final needsAuthentication =
            failure.code == UbaaErrorCode.authenticationRequired ||
            (target == RecoveryTarget.bhpan &&
                failure.code == UbaaErrorCode.permissionDenied &&
                failure.kind == UbaaErrorKind.authentication);
        final backend = session.backend;
        if (!needsAuthentication ||
            !current() ||
            backend is! RequiredTargetSessionBackend ||
            internalWriteCoordinator.hasPendingOperation ||
            internalInteractiveEngaged ||
            !internalAppForeground)
          rethrow;
        // 已有首页恢复先完成，专用服务随后核验自己的目标，不猜需要的路线。
        await internalSessionRecoveryFuture;
        if (!current())
          throw const RecoveryInterrupted(RecoveryStopReason.superseded);
        if (internalWriteCoordinator.hasPendingOperation ||
            internalInteractiveEngaged)
          rethrow;
        final activity = internalActivities.begin(
          ControllerActivityKind.serviceRecovery,
        );
        originalFailure = error;
        originalStack = stack;
        originalLatency = elapsed.elapsed;
        recoveryAttempts++;
        internalWriteCoordinator.invalidate();
        try {
          final result = await internalRecoverTargetSession(
            backend as RequiredTargetSessionBackend,
            target,
            session.lifecycle,
            publishReusedSession: false,
          );
          if (result == null || !current()) {
            throw const RecoveryInterrupted(RecoveryStopReason.superseded);
          }
          await internalRefreshRouteSettings();
          if (!current())
            throw const RecoveryInterrupted(RecoveryStopReason.superseded);
          unawaited(
            internalLoadWriteReadbacks(force: result.sharedBindingRebound),
          );
        } on BackendException catch (failure) {
          if (current() && failure.accountMismatch) {
            await internalRejectMismatchedAccount();
          } else if (current() &&
              failure.captchaRequired &&
              failure.resolvedRoute != null) {
            final input = await internalApprovedRecoveryInput(
              session.lifecycle,
            );
            if (current() && input != null) {
              internalAutomaticCredentialBlocked = true;
              await internalResumeRequiredCaptcha(
                input,
                failure.resolvedRoute!,
              );
            }
          }
          rethrow;
        } finally {
          activity.finish();
          internalDrainDeferredRecovery();
          internalPumpReadTasks();
          if (!internalDisposed) internalNotify();
        }
        if (!current())
          throw const RecoveryInterrupted(RecoveryStopReason.superseded);
        return await checkedRead();
      }
    } on Object catch (error, stack) {
      if (!current() ||
          (error is RecoveryInterrupted &&
              error.reason != RecoveryStopReason.deadline)) {
        throw UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict);
      }
      final original =
          originalFailure == null || identical(originalFailure, error)
          ? null
          : internalRecordServiceFailure(
              originalFailure,
              operation,
              originalStack!,
              latency: originalLatency,
              recoveryAttempts: 0,
            );
      final recorded = internalRecordServiceFailure(
        error,
        operation,
        stack,
        latency: elapsed.elapsed,
        relatedIssueId: original?.issueId,
        recoveryAttempts: recoveryAttempts,
      );
      internalRecordServiceOutcome(operation, error: recorded);
      // 恢复失败仍保留本次已经成功的余额项，不把整组数据变成空白。
      if (partial case final value?) return value;
      throw recorded;
    }
  }
}

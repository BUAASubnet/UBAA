import 'dart:async';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../contracts/backend.dart';
import '../../contracts/recovery.dart';
import '../../contracts/session_recovery.dart';
import '../error_mapper.dart';
import '../state/state.dart';

/// 专用服务复用所需路线恢复；业务读取最多重试一次，写入不进入本流程。
mixin ControllerServiceRecovery on ControllerState {
  @internal
  UiError internalRecordServiceFailure(Object error, StackTrace stack) =>
      internalRecordFailure(error, DiagnosticOperation.read, stackTrace: stack);

  @internal
  Future<T> internalReadService<T>(
    RecoveryTarget target,
    Future<T> Function() read,
  ) async {
    final session = internalCaptureSessionScope();
    final credentialRevision = internalLoginCredentialRevision;
    bool current() =>
        session.isCurrent &&
        credentialRevision == internalLoginCredentialRevision;
    T? partial;
    Future<T> checkedRead({bool recoverMetrics = false}) async {
      if (!current())
        throw const RecoveryInterrupted(RecoveryStopReason.superseded);
      final result = await read();
      if (!current())
        throw const RecoveryInterrupted(RecoveryStopReason.superseded);
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
          if (metric.error case final error?) {
            internalRecordServiceFailure(error, StackTrace.current);
          }
        }
      }
      return result;
    }

    try {
      try {
        return await checkedRead(recoverMetrics: true);
      } on Object catch (error) {
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
        internalWriteTransitions++;
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
          unawaited(internalLoadWriteReadbacks(force: true));
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
          internalWriteTransitions--;
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
      final recorded = internalRecordServiceFailure(error, stack);
      // 恢复失败仍保留本次已经成功的余额项，不把整组数据变成空白。
      if (partial case final value?) return value;
      throw recorded;
    }
  }
}

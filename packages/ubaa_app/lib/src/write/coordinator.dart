import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

import '../contracts/backend.dart';
import '../controller/error_mapper.dart';
import 'receipt_verifier.dart';

typedef WriteCommitter = Future<WriteCommitResult> Function(String intentId);
typedef WritePreparer = Future<WriteIntent> Function();
typedef WriteDiscarder = Future<void> Function(String intentId);
typedef SigninSessionRecovery = Future<bool> Function(BackendException error);
typedef WriteResultObserver =
    void Function(
      WriteOperation operation, {
      required UiError? error,
      required ConnectionMode? route,
    });

/// 唯一生产写流程；Core 仍拥有最终资格与单次网络发送权威。
class WriteCoordinator extends ChangeNotifier {
  WriteCoordinator({
    required WriteCommitter commit,
    WriteDiscarder? discard,
    WriteReceiptVerifier? receiptVerifier,
    this.dismissVerifiedLibraryHint,
    DateTime Function()? now,
    bool Function()? canStart,
    LocalDiagnostics? diagnostics,
    WriteResultObserver? observeResult,
    SigninSessionRecovery? recoverSigninSession,
  }) : _commit = commit,
       _discard = discard,
       _receiptVerifier = receiptVerifier ?? const WriteReceiptVerifier(),
       _now = now ?? DateTime.now,
       _canStart = canStart,
       _observeResult = observeResult,
       _recoverSigninSession = recoverSigninSession,
       _diagnostics = diagnostics ?? LocalDiagnostics();

  final WriteCommitter _commit;
  final WriteDiscarder? _discard;
  final WriteReceiptVerifier _receiptVerifier;
  final Future<void> Function(String id)? dismissVerifiedLibraryHint;
  final DateTime Function() _now;
  final bool Function()? _canStart;
  final LocalDiagnostics _diagnostics;
  final WriteResultObserver? _observeResult;
  final SigninSessionRecovery? _recoverSigninSession;
  WriteState _state = const WriteState.idle();
  bool _disposed = false;
  int _generation = 0;
  Object? _activity;
  final _pendingLibrary = <String, ({WriteIntent intent, String? hintId})>{};

  Set<String> get pendingLibraryLoanIds => _pendingLibrary.keys.toSet();

  void ensureLibraryLoanCanPrepare(String loanId) {
    if (_pendingLibrary.containsKey(loanId)) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
  }

  void clearLibraryReadbacks() => _pendingLibrary.clear();

  void inheritLibraryReadbacks(WriteCoordinator previous) =>
      _pendingLibrary.addAll(previous._pendingLibrary);

  WriteState get state => _state;
  WriteIntent? get intent => _state.intent;
  UiError? get error => _state.error;
  bool get isSubmitting => _state.isSubmitting;

  /// 包括已发布 idle 但尚未完成 finally 的活动，避免认证抢先越过收尾。
  bool get hasPendingOperation => _activity != null || _state.intent != null;

  bool get _mayStart => !_disposed && (_canStart?.call() ?? true);

  void setIntent(WriteIntent intent) {
    if (!_mayStart || _activity != null || _state.intent != null) return;
    if (_pendingLibrary.containsKey(intent.libraryLoanRenewTarget?.loanId))
      return;
    _publish(WriteState(phase: WritePhase.ready, intent: intent));
  }

  Future<WriteIntent?> prepare(WritePreparer prepare) => _prepare(prepare);

  /// 独占一次已由用户确认的批次，保留每个文件的结果。
  Future<T> runConfirmedBatch<T>(Future<T> Function() send) async {
    if (!_mayStart || hasPendingOperation) {
      throw const UiError(
        code: UbaaErrorCode.operationConflict,
        title: '暂时无法提交',
        message: '请等待其他操作结束后再试',
      );
    }
    final generation = _generation;
    final activity = _begin(WritePhase.committing);
    try {
      if (!_isCurrent(activity, generation)) {
        throw const BackendException(UbaaErrorCode.operationConflict);
      }
      return await send();
    } finally {
      _finish(activity);
    }
  }

  Future<WriteIntent?> prepareForUi(
    WritePreparer prepare, {
    required WriteOperation expectedOperation,
  }) async {
    try {
      return await _prepare(
        prepare,
        expectedOperation: expectedOperation,
        recover: expectedOperation == WriteOperation.signinPerform
            ? _recoverSigninSession
            : null,
      );
    } on BackendException catch (exception) {
      throw UbaaErrorMapper.fromException(exception);
    }
  }

  Future<WriteIntent?> _prepare(
    WritePreparer prepare, {
    WriteOperation? expectedOperation,
    SigninSessionRecovery? recover,
  }) async {
    if (!_mayStart || _activity != null || _state.intent != null) return null;
    final generation = _generation;
    final activity = _begin(WritePhase.preparing);
    try {
      if (!_isCurrent(activity, generation) || !_mayStart) return null;
      final prepared = await prepare();
      if (!_isCurrent(activity, generation)) {
        await _discardBestEffort(prepared);
        return null;
      }
      if (expectedOperation != null &&
          prepared.operation != expectedOperation) {
        await _discardBestEffort(prepared);
        throw const BackendException(UbaaErrorCode.internalError);
      }
      if (_pendingLibrary.containsKey(
        prepared.libraryLoanRenewTarget?.loanId,
      )) {
        await _discardBestEffort(prepared);
        throw const BackendException(UbaaErrorCode.operationConflict);
      }
      _publish(WriteState(phase: WritePhase.ready, intent: prepared));
      return _isCurrent(activity, generation) ? prepared : null;
    } on Object catch (exception, stackTrace) {
      if (!_isCurrent(activity, generation)) return null;
      if (recover != null &&
          exception is BackendException &&
          exception.code == UbaaErrorCode.authenticationRequired &&
          exception.resolvedRoute != null &&
          !exception.accountMismatch) {
        // 登录恢复要求写入协调器空闲，恢复完成后重新核对签到资格。
        _finish(activity);
        if (_disposed || _generation != generation || hasPendingOperation)
          return null;
        if (!await recover(exception)) return null;
        return _prepare(prepare, expectedOperation: expectedOperation);
      }
      final error = _safeError(
        exception,
        DiagnosticOperation.writePrepare,
        stackTrace,
        writeOperation: expectedOperation,
      );
      _publish(WriteState(phase: WritePhase.idle, error: error));
      if (!_isCurrent(activity, generation)) return null;
      // 路线已解析才进入学校资格核对的计数；本地表单和权限校验留在本机。
      if (expectedOperation != null && error.resolvedRoute != null) {
        _recordResult(expectedOperation, error: error);
      }
      throw BackendException.fromUi(error);
    } finally {
      _finish(activity);
    }
  }

  Future<void> cancel() => _cancel();

  Future<void> cancelForUi() async {
    try {
      await _cancel();
    } on BackendException catch (exception) {
      throw UbaaErrorMapper.fromException(exception);
    }
  }

  Future<void> _cancel() async {
    final pending = _state.intent;
    if (_disposed || _activity != null || pending == null) return;
    final generation = _generation;
    final activity = _begin(WritePhase.cancelling, intent: pending);
    try {
      final discard = _discard;
      if (discard == null) {
        throw const BackendException(UbaaErrorCode.unsupported);
      }
      await discard(pending.intentId);
      if (_isCurrent(activity, generation)) _publish(const WriteState.idle());
    } on Object catch (exception, stackTrace) {
      if (!_isCurrent(activity, generation)) return;
      final error = _safeError(
        exception,
        DiagnosticOperation.writeDiscard,
        stackTrace,
        writeOperation: pending.operation,
      );
      _publish(
        WriteState(phase: WritePhase.ready, intent: pending, error: error),
      );
      if (!_isCurrent(activity, generation)) return;
      throw BackendException.fromUi(error);
    } finally {
      _finish(activity);
    }
  }

  /// 保留旧返回值和异常类型；安全 UI 入口共享相同的消费路径。
  Future<WriteCommitResult?> confirm() async {
    final completion = await _confirm();
    if (completion?.outcome.error case final error?) {
      throw BackendException.fromUi(error);
    }
    return completion?.outcome.result;
  }

  Future<WriteOutcome?> confirmForUi() async => (await _confirm())?.outcome;

  Future<({WriteOutcome outcome, UbaaErrorCode? code})?> _confirm() async {
    final pending = _state.intent;
    if (!_mayStart || _activity != null || pending == null) return null;
    if (pending.isExpired(_now())) {
      final error = _safeError(
        const BackendException(UbaaErrorCode.intentExpired),
        DiagnosticOperation.writeCommit,
        StackTrace.current,
        writeOperation: pending.operation,
      );
      _publish(
        WriteState(phase: WritePhase.ready, intent: pending, error: error),
      );
      return null;
    }
    final generation = _generation;
    final activity = _begin(WritePhase.committing, intent: pending);
    try {
      if (!_isCurrent(activity, generation) || !_mayStart) {
        await _discardBestEffort(pending);
        return null;
      }
      WriteCommitResult? result;
      UiError? error;
      UiError? resultError;
      String? libraryLoanRejectionReason;
      String? readbackHintId;
      UbaaErrorCode? code;
      try {
        result = await _commit(pending.intentId);
        if (!_isCurrent(activity, generation)) return null;
        if (result.operation != pending.operation) {
          final failure = BackendException(
            UbaaErrorCode.outcomeUnknown,
            resolvedRoute: result.resolvedRoute,
          );
          result = null;
          code = UbaaErrorCode.outcomeUnknown;
          error = _safeError(
            failure,
            DiagnosticOperation.writeCommit,
            StackTrace.current,
            writeOperation: pending.operation,
          );
        } else if (!result.success || result.outcomeUnknown) {
          final failure = BackendException(
            result.outcomeUnknown
                ? UbaaErrorCode.outcomeUnknown
                : result.evaluationResult?.stoppedForUpdate == true
                ? UbaaErrorCode.updateRequired
                : UbaaErrorCode.businessRejected,
            resolvedRoute: result.resolvedRoute,
          );
          resultError = _safeError(
            failure,
            DiagnosticOperation.writeCommit,
            StackTrace.current,
            writeOperation: pending.operation,
          );
        }
      } on Object catch (exception, stackTrace) {
        if (!_isCurrent(activity, generation)) return null;
        if (exception is BackendException)
          readbackHintId = exception.readbackHintId;
        if (pending.operation == WriteOperation.libraryLoanRenew &&
            exception is BackendException &&
            exception.code == UbaaErrorCode.businessRejected) {
          libraryLoanRejectionReason = exception.libraryLoanRejectionReason;
        }
        final unclassified =
            exception is! BackendException && exception is! UiError;
        code = unclassified
            ? UbaaErrorCode.outcomeUnknown
            : _errorCode(exception);
        error = _safeError(
          exception,
          DiagnosticOperation.writeCommit,
          stackTrace,
          writeOperation: pending.operation,
          semanticError: unclassified
              ? UbaaErrorMapper.fromCode(UbaaErrorCode.outcomeUnknown)
              : null,
        );
      }
      if (!_isCurrent(activity, generation)) return null;
      final loanId = pending.libraryLoanRenewTarget?.loanId;
      if (loanId != null &&
          (error?.code == UbaaErrorCode.outcomeUnknown ||
              result?.outcomeUnknown == true)) {
        _pendingLibrary[loanId] = (intent: pending, hintId: readbackHintId);
      }
      _publish(WriteState(phase: WritePhase.readingBack, intent: pending));
      final outcome = await _receiptVerifier.complete(
        pending,
        result: result,
        error: error,
        resultError: resultError,
        libraryLoanRejectionReason: libraryLoanRejectionReason,
        isCurrent: () => _isCurrent(activity, generation),
        onReadbackError: (cause, stackTrace) {
          _safeError(
            cause,
            DiagnosticOperation.readback,
            stackTrace,
            writeOperation: pending.operation,
            relatedIssueId: (error ?? resultError)?.issueId,
          );
        },
      );
      if (!_isCurrent(activity, generation)) return null;
      await _settleLibraryReadback(pending, outcome);
      if (!_isCurrent(activity, generation)) return null;
      _publish(WriteState(phase: WritePhase.idle, error: error));
      if (!_isCurrent(activity, generation)) return null;
      _recordResult(
        pending.operation,
        error: error ?? resultError,
        route: result?.resolvedRoute,
      );
      return _isCurrent(activity, generation)
          ? (outcome: outcome, code: code)
          : null;
    } finally {
      _finish(activity);
    }
  }

  void _recordResult(
    WriteOperation operation, {
    UiError? error,
    ConnectionMode? route,
  }) {
    try {
      _observeResult?.call(operation, error: error, route: route);
    } on Object {
      // 统计回调失败不影响学校写入或界面结果。
    }
  }

  Future<WriteOutcome?> recheckLibraryLoan(String loanId) async {
    final pending = _pendingLibrary[loanId]?.intent;
    if (pending == null || !_mayStart || hasPendingOperation) return null;
    final generation = _generation;
    final activity = _begin(WritePhase.readingBack, intent: pending);
    try {
      final outcome = await _receiptVerifier.complete(
        pending,
        error: UbaaErrorMapper.fromCode(UbaaErrorCode.outcomeUnknown),
        isCurrent: () => _isCurrent(activity, generation),
      );
      if (!_isCurrent(activity, generation)) return null;
      await _settleLibraryReadback(pending, outcome);
      if (!_isCurrent(activity, generation)) return null;
      _publish(const WriteState.idle());
      return outcome;
    } finally {
      _finish(activity);
    }
  }

  Future<void> _settleLibraryReadback(
    WriteIntent intent,
    WriteOutcome outcome,
  ) async {
    final target = intent.libraryLoanRenewTarget;
    final readback = outcome.libraryLoanRenewReadback;
    if (target != null &&
        readback != null &&
        readback.loanId == target.loanId &&
        readback.route == intent.resolvedRoute &&
        readback.status != LibraryRenewStatus.unknown) {
      final id = _pendingLibrary.remove(target.loanId)?.hintId;
      if (id != null) {
        try {
          await dismissVerifiedLibraryHint?.call(id);
        } on Object catch (error, stackTrace) {
          _safeError(
            error,
            DiagnosticOperation.readback,
            stackTrace,
            writeOperation: intent.operation,
          );
        }
      }
    }
  }

  /// 撤销当前会话消费资格，不取消或补偿已经发送的上游写请求。
  void invalidate() {
    if (_disposed) return;
    final pending = _state.phase == WritePhase.ready ? _state.intent : null;
    _generation++;
    _publish(
      _activity == null
          ? const WriteState.idle()
          : const WriteState(phase: WritePhase.invalidating),
    );
    if (pending != null) unawaited(_discardBestEffort(pending));
  }

  Object _begin(WritePhase phase, {WriteIntent? intent}) {
    final activity = Object();
    _activity = activity;
    _publish(WriteState(phase: phase, intent: intent));
    return activity;
  }

  bool _isCurrent(Object activity, int generation) =>
      !_disposed && _generation == generation && identical(_activity, activity);

  void _finish(Object activity) {
    if (!identical(_activity, activity)) return;
    _activity = null;
    if (!_disposed) {
      if (_state.isSubmitting) {
        _publish(const WriteState.idle());
      } else {
        notifyListeners();
      }
    }
  }

  // UI 可合并错误展示，但旧 BackendException 必须保留原协议代码。
  UbaaErrorCode _errorCode(Object exception) => switch (exception) {
    BackendException(:final code) || UiError(:final code) => code,
    _ => UbaaErrorCode.internalError,
  };

  UiError _safeError(
    Object exception,
    DiagnosticOperation operation,
    StackTrace stackTrace, {
    UiError? semanticError,
    WriteOperation? writeOperation,
    String? relatedIssueId,
  }) {
    final error = semanticError ?? UbaaErrorMapper.fromObject(exception);
    if (_disposed) return error;
    try {
      return _diagnostics.record(
        operation: operation,
        error: error,
        feature: writeOperation?.feature,
        writeOperation: writeOperation,
        relatedIssueId: relatedIssueId,
        cause: exception is BackendException ? error : exception,
        stackTrace: stackTrace,
      );
    } on Object {
      return error;
    }
  }

  void _publish(WriteState state) {
    _state = state;
    if (!_disposed) notifyListeners();
  }

  Future<void> _discardBestEffort(WriteIntent pending) async {
    try {
      await _discard?.call(pending.intentId);
    } on Object {
      // 这是失效意图的后台清理，失败不能进入当前代次诊断。
      // 用户主动取消的失败由 _cancel 单独记录；Bridge 自行清理过期意图。
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    final pending = _state.phase == WritePhase.ready ? _state.intent : null;
    _disposed = true;
    _generation++;
    _state = const WriteState.idle();
    if (pending != null) unawaited(_discardBestEffort(pending));
    super.dispose();
  }
}

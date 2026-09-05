import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../contracts/backend.dart';
import '../controller/error_mapper.dart';
import 'receipt_verifier.dart';

typedef WriteCommitter = Future<WriteCommitResult> Function(String intentId);
typedef WritePreparer = Future<WriteIntent> Function();
typedef WriteDiscarder = Future<void> Function(String intentId);

/// 唯一生产写流程；Core 仍拥有最终资格与单次网络发送权威。
class WriteCoordinator extends ChangeNotifier {
  WriteCoordinator({
    required WriteCommitter commit,
    WriteDiscarder? discard,
    WriteReceiptVerifier? receiptVerifier,
    DateTime Function()? now,
    bool Function()? canStart,
  }) : _commit = commit,
       _discard = discard,
       _receiptVerifier = receiptVerifier ?? const WriteReceiptVerifier(),
       _now = now ?? DateTime.now,
       _canStart = canStart;

  final WriteCommitter _commit;
  final WriteDiscarder? _discard;
  final WriteReceiptVerifier _receiptVerifier;
  final DateTime Function() _now;
  final bool Function()? _canStart;
  WriteState _state = const WriteState.idle();
  bool _disposed = false;
  int _generation = 0;
  Object? _activity;

  WriteState get state => _state;
  WriteIntent? get intent => _state.intent;
  UiError? get error => _state.error;
  bool get isSubmitting => _state.isSubmitting;

  bool get _mayStart => !_disposed && (_canStart?.call() ?? true);

  void setIntent(WriteIntent intent) {
    if (!_mayStart || _activity != null || _state.intent != null) return;
    _publish(WriteState(phase: WritePhase.ready, intent: intent));
  }

  Future<WriteIntent?> prepare(WritePreparer prepare) => _prepare(prepare);

  Future<WriteIntent?> prepareForUi(
    WritePreparer prepare, {
    required WriteOperation expectedOperation,
  }) async {
    try {
      return await _prepare(prepare, expectedOperation: expectedOperation);
    } on BackendException catch (exception) {
      throw UbaaErrorMapper.fromCode(exception.code);
    }
  }

  Future<WriteIntent?> _prepare(
    WritePreparer prepare, {
    WriteOperation? expectedOperation,
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
      _publish(WriteState(phase: WritePhase.ready, intent: prepared));
      return _isCurrent(activity, generation) ? prepared : null;
    } on Object catch (exception) {
      if (!_isCurrent(activity, generation)) return null;
      final error = _safeError(exception);
      _publish(WriteState(phase: WritePhase.idle, error: error));
      if (!_isCurrent(activity, generation)) return null;
      throw BackendException(_errorCode(exception));
    } finally {
      _finish(activity);
    }
  }

  Future<void> cancel() => _cancel();

  Future<void> cancelForUi() async {
    try {
      await _cancel();
    } on BackendException catch (exception) {
      throw UbaaErrorMapper.fromCode(exception.code);
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
    } on Object catch (exception) {
      if (!_isCurrent(activity, generation)) return;
      final error = _safeError(exception);
      _publish(
        WriteState(phase: WritePhase.ready, intent: pending, error: error),
      );
      if (!_isCurrent(activity, generation)) return;
      throw BackendException(_errorCode(exception));
    } finally {
      _finish(activity);
    }
  }

  /// 保留旧返回值和异常类型；安全 UI 入口共享相同的消费路径。
  Future<WriteCommitResult?> confirm() async {
    final completion = await _confirm();
    if (completion?.code case final code?) throw BackendException(code);
    return completion?.outcome.result;
  }

  Future<WriteOutcome?> confirmForUi() async => (await _confirm())?.outcome;

  Future<({WriteOutcome outcome, UbaaErrorCode? code})?> _confirm() async {
    final pending = _state.intent;
    if (!_mayStart || _activity != null || pending == null) return null;
    if (pending.isExpired(_now())) {
      _publish(
        WriteState(
          phase: WritePhase.ready,
          intent: pending,
          error: UbaaErrorMapper.fromCode(UbaaErrorCode.intentExpired),
        ),
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
      UbaaErrorCode? code;
      try {
        result = await _commit(pending.intentId);
        if (result.operation != pending.operation) {
          result = null;
          code = UbaaErrorCode.outcomeUnknown;
          error = UbaaErrorMapper.fromCode(code);
        }
      } on Object catch (exception) {
        code = _errorCode(exception);
        error = _safeError(exception);
      }
      if (!_isCurrent(activity, generation)) return null;
      _publish(WriteState(phase: WritePhase.readingBack, intent: pending));
      final outcome = await _receiptVerifier.complete(
        pending,
        result: result,
        error: error,
        isCurrent: () => _isCurrent(activity, generation),
      );
      if (!_isCurrent(activity, generation)) return null;
      _publish(WriteState(phase: WritePhase.idle, error: error));
      return _isCurrent(activity, generation)
          ? (outcome: outcome, code: code)
          : null;
    } finally {
      _finish(activity);
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
    if (!_disposed && _state.isSubmitting) {
      _publish(const WriteState.idle());
    }
  }

  // UI 可合并错误展示，但旧 BackendException 必须保留原协议代码。
  UbaaErrorCode _errorCode(Object exception) => switch (exception) {
    BackendException(:final code) || UiError(:final code) => code,
    _ => UbaaErrorCode.internalError,
  };

  UiError _safeError(Object exception) =>
      UbaaErrorMapper.fromCode(_errorCode(exception));

  void _publish(WriteState state) {
    _state = state;
    if (!_disposed) notifyListeners();
  }

  Future<void> _discardBestEffort(WriteIntent pending) async {
    try {
      await _discard?.call(pending.intentId);
    } on Object {
      // 失效或卸载后不再持有确认资格；Bridge 自行清理过期意图。
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

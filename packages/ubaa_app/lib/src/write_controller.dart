import 'package:flutter/foundation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import 'app_controller.dart';
import 'backend.dart';

typedef WriteCommitter = Future<WriteCommitResult> Function(String intentId);
typedef WritePreparer = Future<WriteIntent> Function();

/// 写入确认状态机。
///
/// intent 由 bridge typed prepare 方法产生；控制器只允许同一 intent 成功提交一次，
/// 不自动重试，也不在后台发起网络请求。
class WriteFlowController extends ChangeNotifier {
  WriteFlowController({required WriteCommitter commit}) : _commit = commit;

  final WriteCommitter _commit;
  WriteIntent? _intent;
  UiError? _error;
  bool _submitting = false;
  bool _disposed = false;

  WriteIntent? get intent => _intent;
  UiError? get error => _error;
  bool get isSubmitting => _submitting;

  void setIntent(WriteIntent intent) {
    if (_disposed) return;
    _intent = intent;
    _error = null;
    _notify();
  }

  /// 执行一次 typed prepare，并把 bridge 返回的意图交给确认页。
  ///
  /// 准备期间不会提交网络写入；已有意图或提交中的流程拒绝并保持原状态。
  Future<WriteIntent?> prepare(WritePreparer prepare) async {
    if (_disposed || _submitting || _intent != null) return null;
    _submitting = true;
    _error = null;
    _notify();
    try {
      final intent = await prepare();
      if (_disposed) return null;
      _intent = intent;
      return intent;
    } on BackendException catch (exception) {
      _error = UbaaErrorMapper.fromCode(exception.code);
      rethrow;
    } on Object {
      _error = UbaaErrorMapper.fromCode(UbaaErrorCode.internalError);
      throw const BackendException(UbaaErrorCode.internalError);
    } finally {
      _submitting = false;
      _notify();
    }
  }

  void cancel() {
    if (_disposed || _submitting) return;
    _intent = null;
    _error = null;
    _notify();
  }

  Future<WriteCommitResult?> confirm() async {
    final intent = _intent;
    if (_disposed || _submitting || intent == null) return null;
    if (intent.isExpired()) {
      _error = UbaaErrorMapper.fromCode(UbaaErrorCode.intentExpired);
      _notify();
      return null;
    }
    _submitting = true;
    _error = null;
    _notify();
    try {
      final result = await _commit(intent.intentId);
      // 无论成功还是服务返回未知结果，intent 都不再可消费；未知结果必须读取核对。
      _intent = null;
      return result;
    } on BackendException catch (exception) {
      // bridge 在 commit 前已原子消费 intent；尤其是 outcome_unknown，
      // 不允许控制器保留旧 intent 造成再次提交。用户必须先走读取核对。
      _intent = null;
      _error = UbaaErrorMapper.fromCode(exception.code);
      rethrow;
    } finally {
      _submitting = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _intent = null;
    super.dispose();
  }
}

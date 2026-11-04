import 'dart:async';
import 'package:ubaa_platform/shared_accounts.dart';
import '../contracts/lifecycle.dart';
import '../contracts/session_recovery.dart';
import 'session_recovery.dart';

/// 一个无界面消费者拥有的资源。普通关闭不调用账号退出或删除共享数据。
final class SharedAccountConsumer {
  SharedAccountConsumer({
    required this.backend,
    required this.accounts,
    this.recovery,
  });
  final BackendLifecycle backend;
  final SharedAccountBackend accounts;
  final RequiredSessionRecovery? recovery;
  bool _closed = false;
  int _writes = 0;
  final _pending = <Future<void>>{};
  bool _bindingBusy = false;
  SharedAccountBinding? _binding;
  bool _settled = false;
  Future<void>? _closing;
  (Object, StackTrace)? _failure;
  bool get isClosed => _closed;

  /// 即使有界 close 已返回，实际资源收尾仍可等待并取得原错误。
  Future<void> get settlement => _closing ?? Future<void>.value();
  Future<T> _track<T>(Future<T> Function() action) {
    if (_closed)
      return Future<T>.error(
        const RecoveryInterrupted(RecoveryStopReason.closed),
      );
    final completion = Completer<void>();
    _pending.add(completion.future);
    final result = Future<T>.sync(action);
    void finish() {
      _pending.remove(completion.future);
      completion.complete();
    }

    // 排空只等待终态；业务结果和原错误仍交给 result 的调用者。
    unawaited(
      result.then<void>(
        (_) => finish(),
        onError: (Object _, StackTrace _) => finish(),
      ),
    );
    return result;
  }

  Future<void> bind(
    SecureLocalAccountStore store,
    LocalAccountSnapshot snapshot, {
    bool requireRestore = true,
  }) => _track(() => _bind(store, snapshot, requireRestore));

  Future<void> _bind(
    SecureLocalAccountStore store,
    LocalAccountSnapshot snapshot,
    bool requireRestore,
  ) async {
    if (_closed) throw const RecoveryInterrupted(RecoveryStopReason.closed);
    if (_writes != 0 || _bindingBusy)
      throw const RecoveryInterrupted(RecoveryStopReason.superseded);
    _bindingBusy = true;
    try {
      final binding = await store.bindSnapshot(
        snapshot,
        requireRestore: requireRestore,
      );
      if (_closed) throw const RecoveryInterrupted(RecoveryStopReason.closed);
      await accounts.bindSharedAccount(binding);
      if (_closed) throw const RecoveryInterrupted(RecoveryStopReason.closed);
      _binding = binding;
    } finally {
      _bindingBusy = false;
    }
  }

  /// 学校写准备、提交及原目标回读共用固定消费者，期间禁止恢复或换绑。
  Future<T> schoolWrite<T>(Future<T> Function() action) =>
      _track(() => _schoolWrite(action));

  Future<T> _schoolWrite<T>(Future<T> Function() action) async {
    final binding = _binding;
    if (_bindingBusy)
      throw const RecoveryInterrupted(RecoveryStopReason.superseded);
    if (_closed || binding == null)
      throw const RecoveryInterrupted(RecoveryStopReason.closed);
    _writes++;
    try {
      await binding.validate();
      return await action();
    } finally {
      _writes--;
    }
  }

  /// 显式全局退出只使用本消费者的原快照，不能撤销另一登录。
  Future<void> logout({bool clearCache = false}) =>
      _track(() => _logout(clearCache: clearCache));

  Future<void> _logout({required bool clearCache}) async {
    final binding = _binding;
    final target = accounts;
    if (_closed ||
        _bindingBusy ||
        binding == null ||
        target is! SharedAccountLogoutBackend)
      throw const RecoveryInterrupted(RecoveryStopReason.superseded);
    _bindingBusy = true;
    _binding = null;
    try {
      final revoked = await binding.accounts.revokeBinding(binding.snapshot);
      await (target as SharedAccountLogoutBackend).logoutSharedAccount(
        revoked,
        clearCache: clearCache,
      );
    } finally {
      _bindingBusy = false;
    }
  }

  Future<RecoveryCloseResult> close({
    Duration grace = const Duration(seconds: 1),
  }) async {
    if (!_closed) {
      _closed = true;
      _closing =
          Future.wait<void>([
            ..._pending,
            if (recovery != null)
              recovery!
                  .close(grace: Duration.zero)
                  .then((_) => recovery!.settlement),
            Future<void>.sync(backend.dispose),
          ]).then<void>(
            (_) {
              _settled = true;
            },
            onError: (Object error, StackTrace stack) {
              _settled = true;
              _failure = (error, stack);
              Error.throwWithStackTrace(error, stack);
            },
          );
      // 有界等待可能先结束；保留原 Future 给 settlement，防止晚到错误无人订阅。
      unawaited(
        _closing!.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
    await _closing!.timeout(grace, onTimeout: () {});
    if (_failure case final failure?)
      Error.throwWithStackTrace(failure.$1, failure.$2);
    return RecoveryCloseResult(_settled ? 0 : 1);
  }
}

import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart' show DiagnosticOperation;
import '../../../contracts/recovery.dart';

/// 页面持有的服务绑定创建时账号代次，账号切换后拒绝旧页面继续请求。
class GuardedIhomeService implements IhomeService {
  GuardedIhomeService(
    this.delegate,
    this.current, {
    this.onRejected,
    this.read,
    this.canWrite,
    this.recordFailure,
    this.recordOutcome,
  });
  final IhomeService delegate;
  final bool Function() current;
  final void Function(Object)? onRejected;
  final ServiceRead? read;
  final bool Function()? canWrite;
  final ServiceFailureRecorder? recordFailure;
  final ServiceOutcomeRecorder? recordOutcome;
  void _check({bool write = false}) {
    if (!current() || (write && canWrite?.call() == false)) {
      throw const UiError(
        code: UbaaErrorCode.operationConflict,
        title: '登录状态已变化',
        message: '登录状态已变化，请重新打开 iHome',
      );
    }
  }

  Future<T> _read<T>(
    DiagnosticOperation operation,
    Future<T> Function() call,
  ) async {
    _check();
    return read?.call(RecoveryTarget.ihome, operation, () => _run(call)) ??
        _run(call);
  }

  Future<T> _run<T>(
    Future<T> Function() call, {
    DiagnosticOperation? writeOperation,
  }) async {
    final write = writeOperation != null;
    _check(write: write);
    try {
      final result = await call();
      _check(write: write);
      if (writeOperation != null) {
        recordOutcome?.call(
          writeOperation,
          write: true,
          route: result is IhomeResult<Object?> ? result.route : null,
        );
      }
      return result;
    } on Object catch (error, stack) {
      if (current() && (!write || canWrite?.call() != false)) {
        onRejected?.call(error);
        if (writeOperation != null) {
          final recorded = recordFailure?.call(error, writeOperation, stack);
          if (recorded != null) {
            recordOutcome?.call(writeOperation, write: true, error: recorded);
            throw recorded;
          }
        }
      }
      rethrow;
    }
  }

  @override
  Future<IhomeResult<IhomePage>> page(IhomeQuery q) =>
      _read(DiagnosticOperation.ihomeList, () => delegate.page(q));
  @override
  Future<IhomeResult<IhomeAppeal>> detail(int id, {bool mine = false}) => _read(
    DiagnosticOperation.ihomeDetail,
    () => delegate.detail(id, mine: mine),
  );
  @override
  Future<IhomeResult<IhomeConfig>> config() =>
      _read(DiagnosticOperation.ihomeConfig, delegate.config);
  @override
  Future<IhomeResult<List<IhomeNotice>>> notices() =>
      _read(DiagnosticOperation.ihomeNotices, delegate.notices);
  @override
  Future<IhomeResult<IhomeNotice>> notice(int id) =>
      _read(DiagnosticOperation.ihomeNotice, () => delegate.notice(id));
  @override
  Future<IhomeResult<IhomeAppeal>> setReaction(
    int id,
    IhomeReaction reaction,
    bool enabled,
    ConnectionMode expectedRoute,
  ) => _run(
    () => delegate.setReaction(id, reaction, enabled, expectedRoute),
    writeOperation: DiagnosticOperation.ihomeReaction,
  );
}

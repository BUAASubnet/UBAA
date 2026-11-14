import 'package:ubaa_domain/ubaa_domain.dart';
import '../../../contracts/recovery.dart';

/// 页面持有的服务绑定创建时账号代次，账号切换后拒绝旧页面继续请求。
class GuardedIhomeService implements IhomeService {
  GuardedIhomeService(
    this.delegate,
    this.current, {
    this.onRejected,
    this.read,
    this.canWrite,
  });
  final IhomeService delegate;
  final bool Function() current;
  final void Function(Object)? onRejected;
  final ServiceRead? read;
  final bool Function()? canWrite;
  void _check({bool write = false}) {
    if (!current() || (write && canWrite?.call() == false)) {
      throw const UiError(
        code: UbaaErrorCode.operationConflict,
        title: '登录状态已变化',
        message: '登录状态已变化，请重新打开 iHome',
      );
    }
  }

  Future<T> _read<T>(Future<T> Function() call) async {
    _check();
    return read?.call(RecoveryTarget.ihome, () => _run(call)) ?? _run(call);
  }

  Future<T> _run<T>(Future<T> Function() call, {bool write = false}) async {
    _check(write: write);
    try {
      final result = await call();
      _check(write: write);
      return result;
    } on Object catch (error) {
      if (current()) onRejected?.call(error);
      rethrow;
    }
  }

  @override
  Future<IhomeResult<IhomePage>> page(IhomeQuery q) =>
      _read(() => delegate.page(q));
  @override
  Future<IhomeResult<IhomeAppeal>> detail(int id, {bool mine = false}) =>
      _read(() => delegate.detail(id, mine: mine));
  @override
  Future<IhomeResult<IhomeConfig>> config() => _read(delegate.config);
  @override
  Future<IhomeResult<List<IhomeNotice>>> notices() => _read(delegate.notices);
  @override
  Future<IhomeResult<IhomeNotice>> notice(int id) =>
      _read(() => delegate.notice(id));
  @override
  Future<IhomeResult<IhomeAppeal>> setReaction(
    int id,
    IhomeReaction reaction,
    bool enabled,
    ConnectionMode expectedRoute,
  ) => _run(
    () => delegate.setReaction(id, reaction, enabled, expectedRoute),
    write: true,
  );
}

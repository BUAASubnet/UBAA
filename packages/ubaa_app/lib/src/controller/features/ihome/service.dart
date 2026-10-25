import 'package:ubaa_domain/ubaa_domain.dart';

/// 页面持有的服务绑定创建时账号代次，账号切换后拒绝旧页面继续请求。
class GuardedIhomeService implements IhomeService {
  GuardedIhomeService(this.delegate, this.current);
  final IhomeService delegate;
  final bool Function() current;
  void _check() {
    if (!current())
      throw const UiError(
        code: UbaaErrorCode.operationConflict,
        title: '会话已变化',
        message: '会话已变化，请返回校园服务重新打开 iHome',
      );
  }

  Future<T> _run<T>(Future<T> Function() call) async {
    _check();
    final result = await call();
    _check();
    return result;
  }

  @override
  Future<IhomeResult<IhomePage>> page(IhomeQuery q) =>
      _run(() => delegate.page(q));
  @override
  Future<IhomeResult<IhomeAppeal>> detail(int id, {bool mine = false}) =>
      _run(() => delegate.detail(id, mine: mine));
  @override
  Future<IhomeResult<IhomeConfig>> config() => _run(delegate.config);
  @override
  Future<IhomeResult<List<IhomeNotice>>> notices() => _run(delegate.notices);
  @override
  Future<IhomeResult<IhomeNotice>> notice(int id) =>
      _run(() => delegate.notice(id));
  @override
  Future<IhomeResult<IhomeAppeal>> setReaction(
    int id,
    IhomeReaction reaction,
    bool enabled,
    ConnectionMode expectedRoute,
  ) => _run(() => delegate.setReaction(id, reaction, enabled, expectedRoute));
}

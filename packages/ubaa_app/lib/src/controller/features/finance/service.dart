import 'package:ubaa_domain/ubaa_domain.dart';

/// 页面前的数据服务，账号或路线代次变化后拒绝旧结果。
class GuardedFinanceService implements FinanceService {
  GuardedFinanceService(this.delegate, this.current);
  final FinanceService delegate;
  final bool Function() current;
  void _check() {
    if (!current())
      throw const UiError(
        code: UbaaErrorCode.operationConflict,
        title: '登录状态已变化',
        message: '请重新打开财务查询',
      );
  }

  @override
  Future<FinanceSnapshot?> cached() async {
    _check();
    final value = await delegate.cached();
    _check();
    return value;
  }

  @override
  Future<FinanceSnapshot> refresh() async {
    _check();
    final value = await delegate.refresh();
    _check();
    return value;
  }
}

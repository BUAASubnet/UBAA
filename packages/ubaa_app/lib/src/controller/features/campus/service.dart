import 'package:ubaa_domain/ubaa_domain.dart';

/// 绑定创建时的账号代次；账号或会话变化后，旧页面的请求与结果都被拒绝。
class GuardedCampusAccountService implements CampusAccountService {
  GuardedCampusAccountService(this.delegate, this.current);
  final CampusAccountService delegate;
  final bool Function() current;

  void _check() {
    if (!current()) {
      throw const UiError(
        code: UbaaErrorCode.operationConflict,
        title: '会话已变化',
        message: '会话已变化，请下拉刷新重新读取',
      );
    }
  }

  Future<T> _run<T>(Future<T> Function() call) async {
    _check();
    final result = await call();
    _check();
    return result;
  }

  /// 本机快照只在账号代次未变时交给页面，失效时返回空快照。
  @override
  Future<CampusAccountSnapshot> cached() async {
    if (!current()) return const CampusAccountSnapshot();
    final value = await delegate.cached();
    return current() ? value : const CampusAccountSnapshot();
  }

  @override
  Future<PortalIdentity> identity() => _run(delegate.identity);
  @override
  Future<CampusMetrics> metrics() => _run(delegate.metrics);
  @override
  Future<NetworkUsage> networkUsage() => _run(delegate.networkUsage);
}

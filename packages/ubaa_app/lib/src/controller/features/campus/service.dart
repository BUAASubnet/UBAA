import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart' show DiagnosticOperation;
import '../../../contracts/recovery.dart';

/// 绑定创建时的账号代次；账号或会话变化后，旧页面的请求与结果都被拒绝。
class GuardedCampusAccountService implements CampusAccountService {
  GuardedCampusAccountService(
    this.delegate,
    this.current, {
    this.onRejected,
    this.read,
  });
  final ServiceRead? read;
  final CampusAccountService delegate;
  final bool Function() current;
  final void Function(Object)? onRejected;

  void _check() {
    if (!current()) {
      throw const UiError(
        code: UbaaErrorCode.operationConflict,
        title: '登录状态已变化',
        message: '登录状态已变化，请下拉刷新',
      );
    }
  }

  Future<T> _run<T>(Future<T> Function() call) async {
    _check();
    try {
      final result = await call();
      _check();
      return result;
    } on Object catch (error) {
      if (current()) onRejected?.call(error);
      rethrow;
    }
  }

  /// 本机快照只在账号代次未变时交给页面，失效时返回空快照。
  @override
  Future<CampusAccountSnapshot> cached() async {
    if (!current()) return const CampusAccountSnapshot();
    final value = await delegate.cached();
    return current() ? value : const CampusAccountSnapshot();
  }

  Future<T> _read<T>(
    RecoveryTarget target,
    DiagnosticOperation operation,
    Future<T> Function() call,
  ) async {
    _check();
    return read?.call(target, operation, () => _run(call)) ?? _run(call);
  }

  @override
  Future<PortalIdentity> identity() => _read(
    RecoveryTarget.portal,
    DiagnosticOperation.portalIdentity,
    delegate.identity,
  );
  @override
  Future<CampusMetrics> metrics() => _read(
    RecoveryTarget.portal,
    DiagnosticOperation.portalMetrics,
    delegate.metrics,
  );
  @override
  Future<NetworkUsage> networkUsage() => _read(
    RecoveryTarget.network,
    DiagnosticOperation.networkUsage,
    delegate.networkUsage,
  );
}

/// 校园卡充值的代次守卫：下单是不可重放的写操作，必须绑定发起时的账号。
class GuardedCampusRechargeService implements CampusRechargeService {
  GuardedCampusRechargeService(this.delegate, this.current);
  final CampusRechargeService delegate;
  final bool Function() current;

  void _check() {
    if (!current()) {
      throw const UiError(
        code: UbaaErrorCode.operationConflict,
        title: '登录状态已变化',
        message: '登录状态已变化，请重新进入充值页面',
      );
    }
  }

  @override
  Future<CampusRechargePreflight> preflight() async {
    _check();
    final value = await delegate.preflight();
    _check();
    return value;
  }

  @override
  Future<CampusRechargeOrder> createOrder({
    required String idserial,
    required String amountFen,
  }) async {
    _check();
    final value = await delegate.createOrder(
      idserial: idserial,
      amountFen: amountFen,
    );
    _check();
    return value;
  }
}

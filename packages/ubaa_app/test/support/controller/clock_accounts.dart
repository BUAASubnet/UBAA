import 'dart:typed_data';
import 'package:ubaa_platform/ubaa_platform.dart';

/// 只为业务时钟测试提供已保存账号，不模拟安全材料事务。
/// 真实文件锁与账号集成继续由 savedAccounts 和 Platform/Host 回归覆盖。
class ClockAccounts implements LocalAccountStore {
  static const _account = LocalAccount(
    id: '00000000000000000000000000000001',
    username: 'fixture-user',
  );
  bool _canRestore = true;
  int _generation = 1;

  @override
  Future<LocalAccountState> read() async => LocalAccountState(
    account: _account,
    canRestore: _canRestore,
    generation: _generation,
  );

  @override
  Future<Uint8List> cacheKey(LocalAccount account) async {
    if (account.id != _account.id || account.username != _account.username) {
      throw StateError('业务时钟测试访问了其他账号');
    }
    return Uint8List(32);
  }

  @override
  Future<void> signOut() async {
    _canRestore = false;
    _generation++;
  }

  @override
  Future<LocalAccountState> retain(
    String username, {
    required bool retainSession,
  }) => throw StateError('业务时钟测试不保存新账号');

  @override
  Future<void> removeAccount(String accountId) =>
      throw StateError('业务时钟测试不删除账号');
}

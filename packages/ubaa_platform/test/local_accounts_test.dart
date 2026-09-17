import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('账号索引可重开，缓存密钥与密码分离，退出不会自动恢复', () async {
    final transport = _MemoryTransport();
    final materials = SecureMaterialStore(transport: transport);
    await materials.probe();
    final accounts = SecureLocalAccountStore(materials);
    expect(await accounts.read(), isNull);
    final saved = await accounts.retain('fixture-user', retainSession: true);
    final key = await accounts.cacheKey(saved.account!);
    expect(key.length, 32);
    expect(saved.canRestore, isTrue);
    expect(saved.toString(), isNot(contains('fixture-user')));
    final reopened = SecureLocalAccountStore(materials);
    expect((await reopened.read())?.account?.id, saved.account!.id);
    await reopened.signOut();
    final signedOut = await accounts.read();
    expect(signedOut?.canRestore, isFalse);
    expect(signedOut!.generation, greaterThan(saved.generation));
    final again = await accounts.retain('fixture-user', retainSession: true);
    expect(again.account?.id, saved.account!.id);
    expect(await accounts.cacheKey(again.account!), key);
  });

  test('换账号不共用密钥，清除账号保留禁止恢复标记', () async {
    final materials = SecureMaterialStore(transport: _MemoryTransport());
    await materials.probe();
    final accounts = SecureLocalAccountStore(materials);
    final a = await accounts.retain('fixture-a', retainSession: true);
    final b = await accounts.retain('fixture-b', retainSession: false);
    expect(b.canRestore, isFalse);
    expect(a.account!.id, isNot(b.account!.id));
    expect(
      await accounts.cacheKey(a.account!),
      isNot(await accounts.cacheKey(b.account!)),
    );
    await accounts.removeAccount(b.account!.id);
    final removed = await accounts.read();
    expect(removed?.account, isNull);
    expect(removed?.canRestore, isFalse);
    await expectLater(
      accounts.cacheKey(b.account!),
      throwsA(isA<SecureMaterialException>()),
    );
    expect(
      (await accounts.retain('fixture-a', retainSession: true)).account?.id,
      a.account!.id,
    );
  });

  test('无法读取密钥不生成替代密钥或伪装账号可恢复', () async {
    final transport = _MemoryTransport();
    final materials = SecureMaterialStore(transport: transport);
    await materials.probe();
    final accounts = SecureLocalAccountStore(materials);
    final a = await accounts.retain('fixture-a', retainSession: true);
    transport.values.removeWhere((key, _) => key.contains('cache-key.'));
    await expectLater(
      accounts.cacheKey(a.account!),
      throwsA(isA<SecureMaterialException>()),
    );
    await expectLater(
      accounts.retain('fixture-a', retainSession: true),
      throwsA(isA<SecureMaterialException>()),
    );
  });
}

class _MemoryTransport implements SecureMaterialTransport {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

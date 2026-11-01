import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('账号索引可重开，缓存密钥与密码分离，退出不会自动恢复', () async {
    final transport = _MemoryTransport();
    final materials = SecureMaterialStore(
      coordinator: _syntheticCoordinator(),
      transport: transport,
    );
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
    final materials = SecureMaterialStore(
      coordinator: _syntheticCoordinator(),
      transport: _MemoryTransport(),
    );
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

  test('已知账号失去缓存密钥仍保留同一日程身份，缓存拒绝生成替代密钥', () async {
    final transport = _MemoryTransport();
    final materials = SecureMaterialStore(
      coordinator: _syntheticCoordinator(),
      transport: transport,
    );
    await materials.probe();
    final accounts = SecureLocalAccountStore(materials);
    final a = await accounts.retain('fixture-a', retainSession: true);
    await accounts.cacheKey(a.account!);
    transport.values.removeWhere((key, _) => key.contains('cache-key.'));
    await expectLater(
      accounts.cacheKey(a.account!),
      throwsA(isA<SecureMaterialException>()),
    );
    final again = await accounts.retain('fixture-a', retainSession: true);
    expect(again.account!.id, a.account!.id);
    await expectLater(
      accounts.cacheKey(again.account!),
      throwsA(isA<SecureMaterialException>()),
    );
    expect(
      transport.values.keys.where((key) => key.contains('cache-key.')),
      isEmpty,
    );
  });

  test('首次保留账号只建立身份，缓存密钥延后到业务缓存打开时创建', () async {
    final transport = _MemoryTransport();
    final materials = SecureMaterialStore(
      coordinator: _syntheticCoordinator(),
      transport: transport,
    );
    await materials.probe();
    final accounts = SecureLocalAccountStore(materials);
    final saved = await accounts.retain('fixture-a', retainSession: true);
    expect(
      transport.values.keys.where((key) => key.contains('cache-key.')),
      isEmpty,
    );
    final reopened = SecureLocalAccountStore(materials);
    expect((await reopened.read())!.account!.id, saved.account!.id);
    expect((await reopened.cacheKey(saved.account!)).length, 32);
  });
  test('旧版索引缺少密钥不会被识别为首次建密钥，也不会换别名', () async {
    final transport = _MemoryTransport();
    final materials = SecureMaterialStore(
      coordinator: _syntheticCoordinator(),
      transport: transport,
    );
    await materials.probe();
    const alias = '00000000000000000000000000000001';
    await materials.write(
      'account-index.v1',
      jsonEncode({
        'version': 1,
        'generation': 1,
        'activeId': alias,
        'canRestore': true,
        'accounts': [
          {'id': alias, 'username': 'fixture-legacy'},
        ],
      }),
    );
    final accounts = SecureLocalAccountStore(materials);
    final saved = await accounts.retain('fixture-legacy', retainSession: true);
    expect(saved.account!.id, alias);
    await expectLater(
      accounts.cacheKey(saved.account!),
      throwsA(isA<SecureMaterialException>()),
    );
    expect(
      transport.values.keys.where((key) => key.contains('cache-key.')),
      isEmpty,
    );
    await materials.write('account-index.v1', '{invalid');
    await expectLater(
      accounts.retain('fixture-legacy', retainSession: true),
      throwsA(isA<SecureMaterialException>()),
    );
    expect(await materials.read('account-index.v1'), '{invalid');
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

MaterialCoordinator _syntheticCoordinator() {
  final directory = Directory.systemTemp.createTempSync(
    'ubaa_synthetic_materials_',
  );
  // 普通异步用例已等待全部账号/材料操作，此时真实文件锁已释放。
  addTearDown(() => directory.delete(recursive: true));
  return MaterialCoordinator(directory: directory);
}

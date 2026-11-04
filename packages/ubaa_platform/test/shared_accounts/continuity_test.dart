import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import '../support/shared_account_worker.dart' show syntheticWindowsMaterials;

void main() {
  late Directory root;
  late SecureLocalAccountStore accounts;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ubaa_synthetic_continuity_');
    final materials = SecureMaterialStore(
      transport: syntheticWindowsMaterials(root),
      coordinator: MaterialCoordinator(
        directory: Directory('${root.path}/lock'),
      ),
    );
    await materials.probe();
    accounts = SecureLocalAccountStore(materials);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test('恢复发布可以续接，退出后同 alias 重登永久拒绝旧连续身份', () async {
    final state = await accounts.retain('fixture-user', retainSession: true);
    final key = await accounts.cacheKey(state.account!);
    final old = (await accounts.capture())!;
    final fresh = await accounts.refreshIfCurrent(old);
    expect(
      (await accounts.recoverySuccessor(old)).state.generation,
      fresh.state.generation,
    );
    await expectLater(
      accounts.revokeIfCurrent(old),
      throwsA(isA<LocalAccountConflict>()),
    );
    expect((await accounts.read())!.canRestore, isTrue);
    await accounts.signOut();
    final again = await accounts.retain('fixture-user', retainSession: true);
    expect(again.account!.id, state.account!.id);
    expect(await accounts.cacheKey(again.account!), key);
    await expectLater(
      accounts.recoverySuccessor(old),
      throwsA(isA<LocalAccountConflict>()),
    );
    await expectLater(
      accounts.recoverySuccessor(fresh),
      throwsA(isA<LocalAccountConflict>()),
    );
  });
  for (final version in [1, 2]) {
    test('v$version 原位升级保留 alias 与已关闭许可，不接受坏连续代次', () async {
      const alias = '00000000000000000000000000000001';
      final old = {
        'version': version,
        'generation': 5,
        'activeId': alias,
        'canRestore': false,
        'accounts': [
          {
            'id': alias,
            'username': 'fixture-user',
            if (version == 2) 'cacheKeyPending': false,
          },
        ],
      };
      await accounts.materials.write('account-index.v1', jsonEncode(old));
      final snapshot = (await accounts.capture())!;
      expect(snapshot.state.account!.id, alias);
      expect(snapshot.state.canRestore, isFalse);
      await expectLater(
        accounts.recoverySuccessor(snapshot),
        throwsA(isA<LocalAccountConflict>()),
      );
      await accounts.revokeIfCurrent(snapshot);
      final value =
          jsonDecode((await accounts.materials.read('account-index.v1'))!)
              as Map<String, dynamic>;
      expect(value['version'], 3);
      expect(value['continuity'], value['generation']);
      value['continuity'] = (value['generation'] as int) + 1;
      await accounts.materials.write('account-index.v1', jsonEncode(value));
      await expectLater(
        accounts.capture(),
        throwsA(isA<SecureMaterialException>()),
      );
    });
  }
}

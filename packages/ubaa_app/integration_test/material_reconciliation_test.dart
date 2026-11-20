import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/recovery.dart' show MemoryMaterials;

const _indexKey = 'ubaa.material.v2.account-index.v1';

void main() {
  test('退出中断后启动对账，仍存活的 Core 句柄拒绝旧代次', () async {
    await RustLib.init();
    final evidence = Directory(Platform.environment['UBAA_UI_EVIDENCE_DIR']!);
    final root = await evidence.createTemp('material-native-');
    addTearDown(() => root.delete(recursive: true));
    final directory = Directory('${root.path}/materials');
    final transport = _InterruptBeforeRevocation();
    SecureLocalAccountStore openAccounts() => SecureLocalAccountStore(
      SecureMaterialStore(
        coordinator: MaterialCoordinator(directory: directory),
        transport: transport,
      ),
    );
    final old = openAccounts();
    await old.materials.probe();
    final state = await old.retain('fixture-user', retainSession: true);
    final account = state.account!;
    await old.cacheKey(account);
    final binding = await old.bindSnapshot((await old.capture())!);
    final scope = await BridgeSharedAccount.capture(
      directory: binding.directory,
      generation: BigInt.from(binding.generation),
      retainSession: true,
    );
    addTearDown(scope.dispose);
    final live = await BridgeAgendaStore.openShared(
      configDir: root.path,
      accountId: account.id,
      scope: scope,
    );
    addTearDown(live.dispose);
    expect(await live.unsyncedCount(), 0);

    transport.interrupt = true;
    await expectLater(old.signOut(), throwsA(isA<SecureMaterialException>()));
    final marker = File('${directory.path}/transaction.v1');
    expect(await marker.readAsString(), 'UBAA1:B:remove');
    transport.interrupt = false;
    expect(
      await openAccounts().reconcileForStartup(),
      MaterialTransactionRecovery.reset,
    );
    expect(await marker.readAsString(), 'UBAA1:C');
    final generation = File('${directory.path}/account-generation.v1');
    expect(await generation.readAsString(), 'UBAA1:${binding.generation + 1}');
    // 在 C 恢复后才访问旧句柄，只核验代次失效，避免 B 提前撤销该句柄。
    await expectLater(
      live.unsyncedCount(),
      throwsA(
        isA<BridgeAgendaError>().having(
          (error) => error.failure,
          'failure',
          BridgeAgendaFailure.superseded,
        ),
      ),
    );
  });
}

final class _InterruptBeforeRevocation extends MemoryMaterials {
  bool interrupt = false;

  @override
  Future<void> write(String key, String value) async {
    if (interrupt && key == _indexKey) throw StateError('合成写入中断');
    await super.write(key, value);
  }
}

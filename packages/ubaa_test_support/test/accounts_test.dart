import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_test_support/materials.dart';
import 'package:ubaa_test_support/recovery.dart';

void main() {
  testWidgets('真实账号 I/O 排空不消耗虚拟业务时间，退出仍撤销同一账号的恢复许可', (tester) async {
    final accounts = await widgetAccounts(tester);
    var expired = false;
    final timer = Timer(
      const Duration(milliseconds: 800),
      () => expired = true,
    );
    addTearDown(timer.cancel);
    final state = (await tester.runAsync(accounts.read))!;
    final key = await tester.runAsync(() => accounts.cacheKey(state.account!));
    expect(key, hasLength(32));
    final signingOut = accounts.signOut();
    await accounts.settle(tester);
    await tester.runAsync(() => signingOut);
    final signedOut = (await tester.runAsync(accounts.read))!;
    expect(signedOut.account!.id, state.account!.id);
    expect(signedOut.canRestore, isFalse);
    expect(signedOut.generation, greaterThan(state.generation));
    expect(expired, isFalse);
    await tester.pump(const Duration(milliseconds: 799));
    expect(expired, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(expired, isTrue);
  });

  test('合成材料清理等待在途写入及真实事务释放锁', () async {
    final transport = _BlockedMaterials();
    final materials = syntheticMaterials(transport);
    await materials.probe();
    transport.block = true;
    final writing = materials.write('synthetic', 'fixture-only');
    await transport.started.future;
    var closed = false;
    final closing = materials.close().then((_) => closed = true);
    await Future<void>.microtask(() {});
    expect(closed, isFalse);
    transport.release.complete();
    await writing;
    await closing;
    expect(closed, isTrue);
    expect(transport.values['ubaa.material.v2.synthetic'], 'fixture-only');
  });
}

class _BlockedMaterials extends MemoryMaterials {
  bool block = false;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write(String key, String value) async {
    if (block) {
      started.complete();
      await release.future;
    }
    await super.write(key, value);
  }
}

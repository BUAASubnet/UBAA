import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/materials.dart';
import 'package:ubaa_test_support/recovery.dart';

void main() {
  for (final automatic in [false, true]) {
    test('恢复首页与同账号重新认证保留登录选项 autoLogin=$automatic', () async {
      final materials = syntheticMaterials(MemoryMaterials());
      await materials.probe();
      final accounts = SecureLocalAccountStore(materials);
      final vault = PlatformCredentialVault(
        store: MaterialCredentialStore(materials),
      );
      final saved = Credential(
        username: 'fixture-user',
        password: 'fixture-secret',
        autoLogin: automatic,
      );
      await vault.write(saved);
      await accounts.retain(saved.username, retainSession: true);
      final controller = AppController(
        backend: FakeRecoveryBackend(),
        localAccountStore: accounts,
        credentialVault: vault,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.phase, AppPhase.home);
      expect(controller.loginForm.rememberPassword, isTrue);
      expect(controller.loginForm.autoLogin, automatic);
      expect(controller.loginForm.password, isEmpty);

      controller.setPassword(saved.password);
      await controller.submitLogin(preserveHome: true);
      expect(controller.phase, AppPhase.home);
      expect(await vault.read(), saved);
      expect((await accounts.read())!.canRestore, isTrue);
      controller.dispose();

      final reopened = AppController(
        backend: FakeRecoveryBackend(),
        localAccountStore: accounts,
        credentialVault: vault,
      );
      addTearDown(reopened.dispose);
      await reopened.initialize();
      expect(reopened.phase, AppPhase.home);
      expect(reopened.loginForm.rememberPassword, isTrue);
      expect(reopened.loginForm.autoLogin, automatic);
    });
  }

  test('本机账号已确认时凭据读取失败仍保留首页与保存材料', () async {
    final accounts = await savedAccounts();
    final vault = _UnreadableCredentialVault();
    final controller = AppController(
      backend: FakeRecoveryBackend(),
      localAccountStore: accounts,
      credentialVault: vault,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.phase, AppPhase.home);
    expect((await accounts.read())!.canRestore, isTrue);
    expect(vault.clearCount, 0);
  });

  test('保存凭据属于另一账号时不恢复其登录选项', () async {
    final controller = AppController(
      backend: FakeRecoveryBackend(),
      localAccountStore: await savedAccounts(),
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: 'another-fixture',
          password: 'fixture-secret',
          autoLogin: true,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.loginForm.username, 'fixture-user');
    expect(controller.loginForm.rememberPassword, isFalse);
    expect(controller.loginForm.autoLogin, isFalse);
    expect(controller.loginForm.password, isEmpty);
  });

  for (final action in ['改填账号', '销毁']) {
    test('恢复首页的凭据读取迟到时保留$action结果', () async {
      final started = Completer<void>();
      final loaded = Completer<Credential?>();
      final controller = AppController(
        backend: FakeRecoveryBackend(),
        localAccountStore: await savedAccounts(),
        credentialVault: CallbackCredentialVault(
          loader: () {
            started.complete();
            return loaded.future;
          },
          saver: (_) async {},
          clearer: () async {},
        ),
      );
      addTearDown(controller.dispose);
      final initializing = controller.initialize();
      await started.future;
      if (action == '改填账号') {
        controller.setUsername('another-fixture');
        controller.setPassword('new-fixture-secret');
      } else {
        controller.dispose();
      }
      loaded.complete(
        const Credential(
          username: 'fixture-user',
          password: 'fixture-secret',
          autoLogin: true,
        ),
      );
      await initializing;
      expect(controller.loginForm.rememberPassword, isFalse);
      expect(controller.loginForm.autoLogin, isFalse);
      if (action == '改填账号') {
        expect(controller.phase, AppPhase.login);
        expect(controller.loginForm.username, 'another-fixture');
        expect(controller.loginForm.password, 'new-fixture-secret');
      } else {
        expect(controller.loginForm.username, isEmpty);
        expect(controller.loginForm.password, isEmpty);
      }
    });
  }

  test('无本机账号且旧凭据读取失败时先登录，手动认证成功后才能进入首页', () async {
    final materials = syntheticMaterials(MemoryMaterials());
    await materials.probe();
    final backend = FakeRecoveryBackend()..signedIn = false;
    final controller = AppController(
      backend: backend,
      localAccountStore: SecureLocalAccountStore(materials),
      credentialVault: _UnreadableCredentialVault(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect(controller.error, isNotNull);
    expect(backend.authCalls, 0);
    expect(backend.loginCalls, 0);
    expect(backend.readCalls, 0);
    controller.setUsername('fixture-user');
    controller.setPassword('fixture-secret');
    await controller.submitLogin();
    expect(backend.loginCalls, 1);
    expect(controller.phase, AppPhase.home);
    expect(controller.user?.username, 'fixture-user');
  });

  test('首次无本机账号且无有效会话时进入登录页，不读取首页', () async {
    final materials = syntheticMaterials(MemoryMaterials());
    await materials.probe();
    final backend = FakeRecoveryBackend()..signedIn = false;
    final controller = AppController(
      backend: backend,
      localAccountStore: SecureLocalAccountStore(materials),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect(backend.loginCalls, 0);
    expect(backend.readCalls, 0);
  });

  test('本机账号索引损坏时停在登录页，不恢复未知账号或启动首页读取', () async {
    final transport = MemoryMaterials();
    final materials = syntheticMaterials(transport);
    await materials.probe();
    final accounts = SecureLocalAccountStore(materials);
    await accounts.retain('fixture-user', retainSession: true);
    transport.values['ubaa.material.v2.account-index.v1'] = '{';
    final backend = FakeRecoveryBackend();
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect(controller.error, isNotNull);
    controller.onHomeFirstFrame();
    await controller.recoverSession();
    expect(backend.authCalls, 0);
    expect(backend.loginCalls, 0);
    expect(backend.readCalls, 0);
    expect(transport.values['ubaa.material.v2.account-index.v1'], '{');
  });

  test('启动恢复对账一致的未完成材料事务并继续恢复账号', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ubaa_material_reconciliation_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final transport = MemoryMaterials();
    final materials = SecureMaterialStore(
      coordinator: MaterialCoordinator(directory: directory),
      transport: transport,
    );
    await materials.probe();
    final accounts = SecureLocalAccountStore(materials);
    final saved = await accounts.retain('fixture-user', retainSession: true);
    await accounts.cacheKey(saved.account!);
    final marker = File('${directory.path}/transaction.v1');
    await marker.writeAsString('UBAA1:B:save', flush: true);

    final controller = AppController(
      backend: FakeRecoveryBackend(),
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize(
      materialRecovery: await accounts.reconcileForStartup(),
    );

    expect(
      controller.phase,
      AppPhase.home,
      reason: controller.diagnostics.records.single.localReason,
    );
    expect(controller.user?.username, 'fixture-user');
    expect(await marker.readAsString(), 'UBAA1:C');
    expect(
      controller.diagnostics.records.single.localReason,
      'material_transaction_reconciled',
    );
  });

  test('能力初始化后留下 B 时控制器拒绝恢复且保留标记', () async {
    final fixture = await _InterruptedMaterials.open();
    final controller = await fixture.start(reconcile: false);
    expect(controller.phase, AppPhase.login);
    expect(await fixture.marker.readAsString(), 'UBAA1:B:save');
  });

  test('退出写入 B 后在索引更新前中断，重启不能返回首页', () async {
    final fixture = await _InterruptedMaterials.open(interrupted: false);
    final before = await fixture.accounts.read();
    fixture.transport.failWrite = 'ubaa.material.v2.account-index.v1';
    await expectLater(
      fixture.accounts.signOut(),
      throwsA(isA<SecureMaterialException>()),
    );
    expect(await fixture.marker.readAsString(), 'UBAA1:B:remove');
    expect(
      await fixture.generation.readAsString(),
      'UBAA1:${before!.generation}',
    );
    fixture.transport.failWrite = null;

    final next = await fixture.start();
    expect(next.phase, AppPhase.login);
    expect(next.user, isNull);
    expect(next.error?.message, '本地登录状态已失效，请重新登录');
    expect(await fixture.marker.readAsString(), 'UBAA1:C');
    expect(
      await fixture.generation.readAsString(),
      'UBAA1:${before.generation + 1}',
    );
    expect(fixture.transport.deletes, fixture.keys);
  });

  test('保存索引已落盘但代次未发布，重启按较大代次撤销', () async {
    final fixture = await _InterruptedMaterials.open(interrupted: false);
    final before = fixture.binding.generation;
    fixture.transport.failIndexReadback = true;
    await expectLater(
      fixture.accounts.refreshIfCurrent(fixture.binding.snapshot),
      throwsA(isA<SecureMaterialException>()),
    );
    expect(await fixture.marker.readAsString(), 'UBAA1:B:save');
    expect(await fixture.generation.readAsString(), 'UBAA1:$before');
    expect(
      fixture.transport.values['ubaa.material.v2.account-index.v1'],
      contains('"generation":${before + 1}'),
    );

    final next = await fixture.start();
    expect(next.phase, AppPhase.login);
    expect(
      next.diagnostics.records.single.localReason,
      'material_transaction_reset',
    );
    expect(await fixture.marker.readAsString(), 'UBAA1:C');
    expect(await fixture.generation.readAsString(), 'UBAA1:${before + 2}');
  });

  test('首次能力探测写入中断后重启进入登录页', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ubaa_probe_restart_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final transport = _FaultyMaterials()..interruptProbe = true;
    SecureMaterialStore openMaterials() => SecureMaterialStore(
      coordinator: MaterialCoordinator(directory: directory),
      transport: transport,
    );
    final first = openMaterials();
    await first.probe();
    expect(first.isAvailable, isFalse);
    final marker = File('${directory.path}/transaction.v1');
    expect(await marker.readAsString(), 'UBAA1:B:probe');
    expect(transport.values, isEmpty);

    final restarted = openMaterials();
    final accounts = SecureLocalAccountStore(restarted);
    final recovery = await accounts.reconcileForStartup();
    expect(recovery, MaterialTransactionRecovery.reconciled);
    expect(await marker.readAsString(), 'UBAA1:C');
    await restarted.probe();
    expect(restarted.isAvailable, isTrue);
    final controller = AppController(
      backend: FakeRecoveryBackend()..signedIn = false,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize(materialRecovery: recovery);
    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect(controller.error, isNull);
    expect(
      controller.diagnostics.records.single.localReason,
      'material_transaction_reconciled',
    );
  });

  group('启动对账撤销本机账号', () {
    for (final failure in ['材料缺失', '删除中断', '代次不一致']) {
      test('$failure 后清理索引引用并废止旧绑定', () async {
        final fixture = await _InterruptedMaterials.open();
        final transport = fixture.transport;
        final accounts = fixture.accounts;
        final before = fixture.binding.generation;
        final expected = failure == '代次不一致' ? before + 3 : before + 1;
        if (failure == '代次不一致') {
          await fixture.generation.writeAsString('UBAA1:${before + 2}');
        } else if (failure == '删除中断') {
          transport.values[fixture.keys.first] = 'synthetic-invalid-key';
        } else {
          transport.values.remove(fixture.keys.first);
        }
        if (failure == '删除中断') {
          transport.failDelete = fixture.keys.last;
          await expectLater(
            fixture.start(),
            throwsA(isA<SecureMaterialException>()),
          );
          expect(await fixture.marker.readAsString(), 'UBAA1:B:remove');
          expect(await fixture.generation.readAsString(), 'UBAA1:$expected');
          expect(transport.values, contains(fixture.keys.last));
          expect(transport.deletes, [fixture.keys.first]);
          transport.failDelete = null;
        }
        final controller = await fixture.start();
        expect(controller.phase, AppPhase.login);
        expect(
          controller.sessionRecoveryStatus,
          SessionRecoveryStatus.needsLogin,
        );
        expect(controller.error?.message, '本地登录状态已失效，请重新登录');
        expect(controller.user, isNull);
        expect(await fixture.marker.readAsString(), 'UBAA1:C');
        expect(await fixture.generation.readAsString(), 'UBAA1:$expected');
        final reset = (await accounts.read())!;
        expect(reset.account, isNull);
        expect(reset.canRestore, isFalse);
        expect(reset.generation, expected);
        for (final key in fixture.keys) {
          expect(transport.values, isNot(contains(key)));
        }
        expect(
          transport.deletes,
          failure == '材料缺失' ? [fixture.keys.last] : fixture.keys,
        );
        expect(transport.values['ubaa.material.v2.other'], 'synthetic-other');
        await expectLater(
          fixture.binding.validate(),
          throwsA(isA<LocalAccountConflict>()),
        );
        expect(controller.diagnostics.records.map((r) => r.localReason), [
          'material_transaction_reset',
        ]);
        final next = await accounts.retain('fixture-new', retainSession: true);
        expect(next.generation, expected + 1);
      });
    }

    test('待首次建密钥的账号在密钥缺失时仍可继续恢复', () async {
      final fixture = await _InterruptedMaterials.open(pendingKey: true);
      final next = await fixture.start();
      expect(next.phase, AppPhase.home);
      expect(await fixture.marker.readAsString(), 'UBAA1:C');
      expect(
        await fixture.generation.readAsString(),
        'UBAA1:${fixture.binding.generation}',
      );
    });

    test('删除首个材料失败后，代次已相等仍须完成清理', () async {
      final fixture = await _InterruptedMaterials.open();
      final before = fixture.binding.generation;
      await fixture.generation.writeAsString('UBAA1:${before - 1}');
      fixture.transport.failDelete = fixture.keys.first;
      await expectLater(
        fixture.start(),
        throwsA(isA<SecureMaterialException>()),
      );
      expect(await fixture.marker.readAsString(), 'UBAA1:B:remove');
      expect(await fixture.generation.readAsString(), 'UBAA1:${before + 1}');
      expect(fixture.transport.deletes, isEmpty);
      expect(fixture.keys.every(fixture.transport.values.containsKey), isTrue);
      fixture.transport.failDelete = null;
      final controller = await fixture.start();
      expect(controller.error?.message, '本地登录状态已失效，请重新登录');
      expect(fixture.transport.deletes, fixture.keys);
      expect(await fixture.marker.readAsString(), 'UBAA1:C');
      expect(await fixture.generation.readAsString(), 'UBAA1:${before + 1}');
    });

    test('空索引写入后读回失败，重试保留重新登录提示', () async {
      final fixture = await _InterruptedMaterials.open();
      final transport = fixture.transport;
      transport.values.remove(fixture.keys.first);
      transport.failResetReadback = true;
      await expectLater(
        fixture.start(),
        throwsA(isA<SecureMaterialException>()),
      );
      expect(await fixture.marker.readAsString(), 'UBAA1:B:remove');
      expect(transport.deletes, [fixture.keys.last]);
      final controller = await fixture.start();
      expect(controller.error?.message, '本地登录状态已失效，请重新登录');
      expect(await fixture.marker.readAsString(), 'UBAA1:C');
      expect(transport.deletes, [fixture.keys.last]);
      final current = fixture.binding.generation + 1;
      expect(await fixture.generation.readAsString(), 'UBAA1:$current');
      final state = await fixture.accounts.retain(
        'fixture-new',
        retainSession: true,
      );
      expect(state.generation, current + 1);
      expect((await fixture.accounts.read())?.canRestore, isTrue);
    });

    for (final failure in ['索引损坏', '索引缺失', '代次损坏', '代次缺失', '读取失败', '写入失败']) {
      test('$failure 时保留 B 和全部剩余材料', () async {
        final fixture = await _InterruptedMaterials.open();
        final transport = fixture.transport;
        const indexKey = 'ubaa.material.v2.account-index.v1';
        switch (failure) {
          case '索引损坏':
            transport.values[indexKey] = '{';
          case '索引缺失':
            transport.values.remove(indexKey);
          case '代次损坏':
            await fixture.generation.writeAsString('UBAA1:invalid');
          case '代次缺失':
            await fixture.generation.delete();
          case '读取失败':
            transport.values.remove(fixture.keys.first);
            transport.failRead = fixture.keys.last;
          case '写入失败':
            transport.values.remove(fixture.keys.first);
            transport.failWrite = indexKey;
        }
        final before = Map.of(transport.values);
        final generation = await fixture.generation.exists()
            ? await fixture.generation.readAsString()
            : null;
        await expectLater(
          fixture.start(),
          throwsA(
            failure == '读取失败' || failure == '写入失败'
                ? isA<SecureMaterialException>().having(
                    (error) => error.runtimeType,
                    '传输失败类型',
                    SecureMaterialException,
                  )
                : isA<MaterialTransactionUnrecoverable>(),
          ),
        );
        expect(transport.values, before);
        expect(transport.deletes, isEmpty);
        expect(await fixture.generation.exists(), generation != null);
        if (generation != null) {
          expect(await fixture.generation.readAsString(), generation);
        }
        expect(
          await fixture.marker.readAsString(),
          failure == '写入失败' ? 'UBAA1:B:remove' : 'UBAA1:B:save',
        );
      });
    }
  });

  test('本机账号先进入首页，首帧前不等待认证，首帧后立即合并恢复', () async {
    final accounts = await savedAccounts();
    final backend = FakeRecoveryBackend()..gate = Completer<AuthStatus>();
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.phase, AppPhase.home);
    expect(backend.authCalls, 0);
    controller.onHomeFirstFrame();
    final first = controller.recoverSession();
    final second = controller.recoverSession();
    expect(identical(first, second), isTrue);
    expect(backend.authCalls, 1);
    expect(controller.phase, AppPhase.home);
    backend.gate!.complete(AuthStatus.signedIn);
    await first;
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
    expect(backend.loginCalls, 0);
  });

  test('原位登录失败保留首页与导航生命期，清空临时密码', () async {
    final backend = FakeRecoveryBackend()..signedIn = false;
    final controller = AppController(
      backend: backend,
      localAccountStore: await savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    final epoch = controller.readCacheEpoch;
    backend.loginError = const BackendException(
      UbaaErrorCode.invalidCredentials,
    );
    controller.setPassword('fixture-secret');
    await controller.submitLogin(preserveHome: true);
    expect(controller.phase, AppPhase.home);
    expect(controller.readCacheEpoch, epoch);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.needsLogin);
    expect(controller.loginForm.password, isEmpty);
  });

  test('本地首页与恢复完成不会自动准备或提交此前点击的写操作', () async {
    final backend = FakeRecoveryBackend()..gate = Completer<AuthStatus>();
    final controller = AppController(
      backend: backend,
      localAccountStore: await savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    var attempts = 0;
    Future<WriteIntent> prepare() async {
      attempts++;
      throw StateError('不应进入学校准备');
    }

    expect(await controller.writeCoordinator.prepare(prepare), isNull);
    final recovering = controller.recoverSession();
    expect(await controller.writeCoordinator.prepare(prepare), isNull);
    backend.gate!.complete(AuthStatus.signedIn);
    await recovering;
    expect(attempts, 0);
    expect(controller.writeCoordinator.intent, isNull);
  });

  test('原位登录迟到不能撤销主动退出或重新激活本机账号', () async {
    final accounts = await savedAccounts();
    final backend = FakeRecoveryBackend()..signedIn = false;
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    backend.loginGate = Completer<void>();
    controller.setPassword('fixture-secret');
    final loggingIn = controller.submitLogin(preserveHome: true);
    await controller.logout();
    backend.loginGate!.complete();
    await loggingIn;
    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect((await accounts.read())?.canRestore, isFalse);
  });

  test('原位手动登录返回另一账号时不绑定到本机索引或展示该资料', () async {
    final accounts = await savedAccounts();
    final backend = FakeRecoveryBackend()..signedIn = false;
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    backend.username = 'another-fixture';
    controller.setPassword('fixture-secret');
    await controller.submitLogin(preserveHome: true);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.needsLogin);
    expect(controller.user, isNull);
    expect((await accounts.read())?.canRestore, isFalse);
    expect(backend.readCalls, 0);
  });

  test('旧 autoLogin 关闭不阻止会话检查，但不能自动提交旧密码', () async {
    final backend = FakeRecoveryBackend()..signedIn = false;
    final controller = AppController(
      backend: backend,
      localAccountStore: await savedAccounts(),
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: 'fixture-user',
          password: 'fixture-secret',
          autoLogin: false,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    expect(backend.authCalls, 1);
    expect(backend.loginCalls, 0);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.needsLogin);
    expect(controller.phase, AppPhase.home);
    expect(controller.loginForm.password, isEmpty);
  });

  test('获准凭据只在会话明确失效后使用且失败仍保留首页', () async {
    final backend = FakeRecoveryBackend()..signedIn = false;
    final controller = AppController(
      backend: backend,
      localAccountStore: await savedAccounts(),
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: 'fixture-user',
          password: 'fixture-secret',
          autoLogin: true,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    expect(backend.loginCalls, 1);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
    expect(controller.phase, AppPhase.home);
    expect(controller.loginForm.password, isEmpty);
  });

  test('网络失败不提交密码，不把本地首页换回登录页', () async {
    final backend = FakeRecoveryBackend()
      ..authError = const BackendException(UbaaErrorCode.networkError);
    final controller = AppController(
      backend: backend,
      localAccountStore: await savedAccounts(),
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: 'fixture-user',
          password: 'fixture-secret',
          autoLogin: true,
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    expect(controller.phase, AppPhase.home);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.unavailable);
    expect(backend.loginCalls, 0);
  });

  test('恢复期间主动退出，迟到认证不能重开首页或重新启用账号', () async {
    final accounts = await savedAccounts();
    final backend = FakeRecoveryBackend()..gate = Completer<AuthStatus>();
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final recovery = controller.recoverSession();
    await controller.logout();
    backend.gate!.complete(AuthStatus.signedIn);
    await recovery;
    expect(controller.phase, AppPhase.login);
    expect(controller.user, isNull);
    expect((await accounts.read())?.canRestore, isFalse);
    final reopened = AppController(
      backend: FakeRecoveryBackend(),
      localAccountStore: accounts,
    );
    addTearDown(reopened.dispose);
    await reopened.initialize();
    expect(reopened.phase, AppPhase.login);
  });

  test('认证身份与本机账号不符，停止投影并关闭旧账号恢复', () async {
    final accounts = await savedAccounts();
    final backend = FakeRecoveryBackend()..username = 'another-fixture';
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    expect(controller.user, isNull);
    expect(controller.phase, AppPhase.login);
    expect((await accounts.read())?.canRestore, isFalse);
    expect(backend.readCalls, 0);
  });
}

final class _InterruptedMaterials {
  _InterruptedMaterials(
    this.transport,
    this.accounts,
    this.binding,
    this.keys,
    this.marker,
    this.generation,
  );

  final _FaultyMaterials transport;
  final SecureLocalAccountStore accounts;
  final SharedAccountBinding binding;
  final List<String> keys;
  final File marker;
  final File generation;

  static Future<_InterruptedMaterials> open({
    bool pendingKey = false,
    bool interrupted = true,
  }) async {
    final dir = await Directory.systemTemp.createTemp(
      'ubaa_material_reconciliation_',
    );
    addTearDown(() => dir.delete(recursive: true));
    final transport = _FaultyMaterials()
      ..values['ubaa.material.v2.other'] = 'synthetic-other';
    final materials = SecureMaterialStore(
      coordinator: MaterialCoordinator(directory: dir),
      transport: transport,
    );
    await materials.probe();
    transport.deletes.clear();
    final accounts = SecureLocalAccountStore(materials);
    final keys = <String>[];
    for (final user in ['fixture-first', 'fixture-second']) {
      final account = (await accounts.retain(
        user,
        retainSession: true,
      )).account!;
      if (!pendingKey) await accounts.cacheKey(account);
      keys.add('ubaa.material.v2.cache-key.${account.id}');
    }
    final binding = await accounts.bindSnapshot((await accounts.capture())!);
    final marker = File('${dir.path}/transaction.v1');
    final generation = File('${dir.path}/account-generation.v1');
    if (interrupted) await marker.writeAsString('UBAA1:B:save', flush: true);
    return _InterruptedMaterials(
      transport,
      accounts,
      binding,
      keys,
      marker,
      generation,
    );
  }

  Future<AppController> start({bool reconcile = true}) async {
    final materials = SecureMaterialStore(
      coordinator: MaterialCoordinator(directory: marker.parent),
      transport: transport,
    );
    final startupAccounts = SecureLocalAccountStore(materials);
    final recovery = reconcile
        ? await startupAccounts.reconcileForStartup()
        : null;
    final startupStore = reconcile ? startupAccounts : accounts;
    if (reconcile) await materials.probe();
    transport.deletes.removeWhere((key) => key.contains('.capability.'));
    final backend = FakeRecoveryBackend();
    final controller = AppController(
      backend: backend,
      localAccountStore: startupStore,
    );
    addTearDown(controller.dispose);
    await controller.initialize(materialRecovery: recovery);
    expect(backend.authCalls, 0);
    return controller;
  }
}

final class _FaultyMaterials extends MemoryMaterials {
  final deletes = <String>[];
  String? failRead;
  String? failWrite;
  String? failDelete;
  bool failResetReadback = false;
  bool failIndexReadback = false;
  bool interruptProbe = false;

  @override
  Future<String?> read(String key) async {
    if (key == failRead) {
      failRead = null;
      throw StateError('合成读取失败');
    }
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (key == failWrite) throw StateError('合成写入失败');
    if (interruptProbe && key.contains('.capability.')) {
      interruptProbe = false;
      throw StateError('合成探测中断');
    }
    await super.write(key, value);
    if (key.endsWith('account-index.v1') &&
        (failIndexReadback ||
            (failResetReadback && value.contains('"accounts":[]')))) {
      failResetReadback = false;
      failIndexReadback = false;
      failRead = key;
    }
  }

  @override
  Future<void> delete(String key) async {
    if (key == failDelete) throw StateError('合成删除失败');
    if (!values.containsKey(key)) throw StateError('合成传输不支持删除缺失键');
    deletes.add(key);
    await super.delete(key);
  }
}

class _UnreadableCredentialVault extends MemoryCredentialVault {
  @override
  Future<Credential?> load() async => throw const CredentialVaultException(
    CredentialVaultErrorCode.storageFailure,
  );
}

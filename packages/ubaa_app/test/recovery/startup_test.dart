import 'package:ubaa_test_support/materials.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
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

class _UnreadableCredentialVault extends MemoryCredentialVault {
  @override
  Future<Credential?> load() async => throw const CredentialVaultException(
    CredentialVaultErrorCode.storageFailure,
  );
}

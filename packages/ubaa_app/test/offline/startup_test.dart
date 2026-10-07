import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('无本机账号且旧凭据读取失败时先登录，手动认证成功后才能进入首页', () async {
    final materials = SecureMaterialStore(transport: MemoryMaterials());
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
    final materials = SecureMaterialStore(transport: MemoryMaterials());
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
    final materials = SecureMaterialStore(transport: transport);
    await materials.probe();
    final accounts = SecureLocalAccountStore(materials);
    await accounts.retain('fixture-user', retainSession: true);
    transport.values['ubaa.material.v1.account-index.v1'] = '{';
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
    expect(transport.values['ubaa.material.v1.account-index.v1'], '{');
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

Future<LocalAccountStore> savedAccounts() async {
  final materials = SecureMaterialStore(transport: MemoryMaterials());
  await materials.probe();
  final accounts = SecureLocalAccountStore(materials);
  await accounts.retain('fixture-user', retainSession: true);
  return accounts;
}

class _UnreadableCredentialVault extends MemoryCredentialVault {
  @override
  Future<Credential?> load() async => throw const CredentialVaultException(
    CredentialVaultErrorCode.storageFailure,
  );
}

class MemoryMaterials implements SecureMaterialTransport {
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

class FakeRecoveryBackend implements UbaaBackend {
  Completer<AuthStatus>? gate;
  Completer<void>? loginGate;
  BackendException? authError;
  BackendException? loginError;
  bool signedIn = true;
  String username = 'fixture-user';
  int authCalls = 0;
  int loginCalls = 0;
  int readCalls = 0;
  @override
  Future<AuthStatus> authStatus() async {
    authCalls++;
    if (authError case final error?) throw error;
    if (gate case final pending?) return pending.future;
    return signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;
  }

  @override
  Future<UserSummary?> userInfo() async => UserSummary(username: username);
  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}
  @override
  Future<void> login(LoginInput input) async {
    loginCalls++;
    if (loginError case final error?) throw error;
    if (loginGate case final pending?) await pending.future;
    signedIn = true;
  }

  @override
  Future<void> logout() async {
    signedIn = false;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    readCalls++;
    return const FeatureResult.empty();
  }
}

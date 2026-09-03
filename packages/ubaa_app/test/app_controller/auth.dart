part of '../app_controller_test.dart';

void _registerAuthTests() {
  test('登录后独立加载普通与高级只读功能', () async {
    final controller = AppController(
      backend: DemoBackend(loginDelay: Duration.zero),
      credentialVault: MemoryCredentialVault(),
    );
    await controller.initialize();
    expect(controller.phase, AppPhase.login);
    controller.setUsername('2020000000');
    controller.setPassword('not-a-real-password');
    await controller.submitLogin();
    expect(controller.phase, AppPhase.home);
    await controller.refreshHome();
    expect(
      controller.snapshots.values.every(
        (snapshot) => snapshot.status == FeatureLoadStatus.success,
      ),
      isTrue,
    );
    controller.dispose();
  });

  test('生产能力不可用时不伪造 Demo 登录成功', () async {
    final controller = AppController(backend: const UnavailableBackend());
    await controller.initialize();
    expect(controller.phase, AppPhase.login);
    expect(controller.error?.code, UbaaErrorCode.unsupported);
    controller.dispose();
  });

  test('安全保险箱明确开启自动登录时恢复会话并清理密码', () async {
    final controller = AppController(
      backend: DemoBackend(loginDelay: Duration.zero),
      credentialVault: MemoryCredentialVault(
        initial: const Credential(
          username: '2020000000',
          password: 'saved-secret',
          autoLogin: true,
        ),
      ),
    );
    await controller.initialize();
    expect(controller.phase, AppPhase.home);
    expect(controller.user?.username, '2020000000');
    expect(controller.loginForm.password, isEmpty);
    expect(controller.loginForm.autoLogin, isTrue);
    controller.dispose();
  });

  test('退出登录与退出并清除本机账号保持分离', () async {
    final vault = MemoryCredentialVault(
      initial: const Credential(
        username: '2020000000',
        password: 'saved-secret',
      ),
    );
    final controller = AppController(
      backend: DemoBackend(loginDelay: Duration.zero),
      credentialVault: vault,
    );
    await controller.initialize();

    await controller.logout();
    expect(vault.hasValue, isTrue);
    await controller.logout(clearSavedCredential: true);
    expect(vault.hasValue, isFalse);
    controller.dispose();
  });

  test('错误映射不暴露上游细节', () {
    final error = UbaaErrorMapper.fromCode(UbaaErrorCode.networkError);
    expect(error.message, contains('校园网'));
    expect(error.message, isNot(contains('http')));
    expect(error.retryable, isTrue);
  });
}

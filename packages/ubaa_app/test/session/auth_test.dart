import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void _registerAuthTests() {
  test('登录后先加载首页，其他功能保持待访问', () async {
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
      controller.homeSnapshots.values
          .where(
            (s) => [
              FeatureId.schedule,
              FeatureId.signin,
              FeatureId.spoc,
              FeatureId.judge,
              FeatureId.ygdk,
            ].contains(s.feature),
          )
          .every((snapshot) => snapshot.status == FeatureLoadStatus.success),
      isTrue,
    );
    expect(
      controller.snapshots[FeatureId.exam]!.status,
      FeatureLoadStatus.idle,
    );
    controller.dispose();
  });

  test('生产能力不可用时不伪造 Demo 登录成功', () async {
    final controller = AppController(backend: const UnavailableBackend());
    await controller.initialize();
    expect(controller.phase, AppPhase.login);
    expect(controller.error?.code, UbaaErrorCode.internalError);
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
    expect(error.message, contains('网络'));
    expect(error.message, isNot(contains('http')));
    expect(error.retryable, isTrue);
  });
}

void main() {
  _registerAuthTests();
}

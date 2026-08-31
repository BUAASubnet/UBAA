import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('登录后独立加载八个只读功能', () async {
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

  test('错误映射不暴露上游细节', () {
    final error = UbaaErrorMapper.fromCode(UbaaErrorCode.networkError);
    expect(error.message, contains('校园网'));
    expect(error.message, isNot(contains('http')));
    expect(error.retryable, isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';

void main() {
  test('DemoBackend 提供确定性的登录与只读功能夹具', () async {
    final backend = DemoBackend(loginDelay: Duration.zero);

    expect(await backend.authStatus(), AuthStatus.signedOut);
    expect(await backend.userInfo(), isNull);

    await backend.login(
      const LoginInput(username: '2020000000', password: 'demo-password'),
    );

    expect(await backend.authStatus(), AuthStatus.signedIn);
    expect((await backend.userInfo())?.username, '2020000000');

    final result = await backend.loadFeature(FeatureId.schedule);
    expect(result.summary, '今天有 3 节课程');
    expect(result.details.single.title, FeatureId.schedule.title);

    await backend.logout();
    expect(await backend.authStatus(), AuthStatus.signedOut);
    expect(await backend.userInfo(), isNull);
  });

  test('DemoBackend 拒绝空凭据并阻止未登录读取', () async {
    final backend = DemoBackend(loginDelay: Duration.zero);

    await expectLater(
      backend.login(const LoginInput(username: '', password: 'password')),
      throwsA(isA<BackendException>()),
    );
    await expectLater(
      backend.loadFeature(FeatureId.schedule),
      throwsA(isA<BackendException>()),
    );
  });
}

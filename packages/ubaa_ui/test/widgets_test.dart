import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('启动页展示品牌且登录页不猜测验证码流程', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: UbaaTheme.light(), home: const UbaaSplashView()),
    );

    expect(find.text('UBAA'), findsOneWidget);
    expect(find.text('Make BUAA Great Again'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaLoginView(
          username: '',
          password: '',
          captcha: '',
          rememberPassword: false,
          autoLogin: false,
          routePolicy: RoutePolicy.auto,
          error: null,
          isLoading: false,
          credentialPersistenceAvailable: false,
          onUsernameChanged: (_) {},
          onPasswordChanged: (_) {},
          onCaptchaChanged: (_) {},
          onRememberPasswordChanged: (_) {},
          onAutoLoginChanged: (_) {},
          onRoutePolicyChanged: (_) {},
          onSubmit: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('UBAA 登录'), findsOneWidget);
    expect(find.text('验证码'), findsNothing);
    expect(find.textContaining('安全存储'), findsOneWidget);
  });
}

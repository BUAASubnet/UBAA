import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('真实登录控件展示路线图片并把点击刷新交给对应路线', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final refreshed = <ConnectionMode>[];
    await tester.pumpWidget(_login(onRefresh: refreshed.add));
    await tester.pumpAndSettle();
    expect(find.text('WebVPN 验证码'), findsOneWidget);
    expect(find.byKey(const ValueKey('captcha-image-webvpn')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('captcha-image-webvpn')));
    expect(refreshed, <ConnectionMode>[ConnectionMode.webvpn]);
    expect(find.text('保持自动连接并继续'), findsOneWidget);
    expect(find.text('改用直连并继续'), findsOneWidget);
    expect(find.text('synthetic-account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _login({required ValueChanged<ConnectionMode> onRefresh}) => MaterialApp(
  home: UbaaLoginView(
    username: 'synthetic-account',
    password: 'synthetic-password',
    captcha: '',
    rememberPassword: true,
    autoLogin: false,
    routePolicy: RoutePolicy.auto,
    error: null,
    isLoading: false,
    credentialPersistenceAvailable: true,
    onUsernameChanged: (_) {},
    onPasswordChanged: (_) {},
    onCaptchaChanged: (_) {},
    onRememberPasswordChanged: (_) {},
    onAutoLoginChanged: (_) {},
    onRoutePolicyChanged: (_) {},
    onSubmit: () {},
    onRefreshCaptcha: onRefresh,
    onCaptchaAnswerChanged: (_, _) {},
    onContinueReady: (_) {},
    verification: LoginVerificationState(
      routes: <LoginRouteVerification>[
        const LoginRouteVerification(
          route: ConnectionMode.direct,
          status: LoginRouteVerificationStatus.ready,
        ),
        LoginRouteVerification(
          route: ConnectionMode.webvpn,
          status: LoginRouteVerificationStatus.captchaRequired,
          revision: 1,
          validFor: const Duration(seconds: 120),
          frame: CaptchaPixelFrame(
            width: 1,
            height: 1,
            rgba: Uint8List.fromList(<int>[17, 83, 149, 255]),
          ),
        ),
      ],
    ),
  ),
);

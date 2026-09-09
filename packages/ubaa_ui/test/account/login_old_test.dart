import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('旧登录忙碌时按钮及键盘完成均不再次提交', (tester) async {
    var submits = 0;
    await tester.pumpWidget(_login(loading: true, submit: () => submits++));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNull,
    );
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, '密码'),
    );
    field.onSubmitted?.call('synthetic-password');
    expect(submits, 0);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == '显示密码',
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('登录路线仅右上单图标，菜单说明默认策略并非实际路线', (tester) async {
    await tester.pumpWidget(_login());
    expect(find.textContaining('模式：'), findsNothing);
    await tester.tap(find.byTooltip('连接模式'));
    await tester.pumpAndSettle();
    expect(find.text('尚未读取；这里设置登录与后续查询的默认策略。'), findsOneWidget);
    expect(find.text('WebVPN'), findsOneWidget);
    expect(find.text('直连'), findsOneWidget);
  });

  testWidgets('短窗口大字登录表单保留顶部安全空间并可滚到登录', (tester) async {
    tester.view.physicalSize = const Size(390, 390);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_login());
    expect(
      tester.getRect(find.text('UBAA 登录')).top,
      greaterThanOrEqualTo(tester.getRect(find.byTooltip('连接模式')).bottom),
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, '登录').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _login({bool loading = false, VoidCallback? submit}) => MaterialApp(
  theme: UbaaTheme.light(),
  home: UbaaLoginView(
    username: 'account-fixture',
    password: 'synthetic-password',
    captcha: '',
    rememberPassword: false,
    autoLogin: false,
    routePolicy: RoutePolicy.auto,
    error: null,
    isLoading: loading,
    credentialPersistenceAvailable: true,
    onUsernameChanged: (_) {},
    onPasswordChanged: (_) {},
    onCaptchaChanged: (_) {},
    onRememberPasswordChanged: (_) {},
    onAutoLoginChanged: (_) {},
    onRoutePolicyChanged: (_) {},
    onSubmit: submit ?? () {},
  ),
);

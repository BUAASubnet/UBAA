part of '../ui_account_test.dart';

void _registerLoginOld(IntegrationTestWidgetsFlutterBinding binding) {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('原生旧登录顺序与单路线图标 ${brightness.name}/$scale', (tester) async {
        final backend = _AccountBackend();
        await _mountAccount(
          tester,
          backend,
          MemoryCredentialVault(),
          brightness,
          scale: scale,
        );
        final tag =
            'login-${brightness.name}-${scale == 1 ? 'normal' : 'large'}';
        expect(find.textContaining('模式：'), findsNothing);
        expect(find.byType(TextField), findsNWidgets(2));
        await _accountShot(binding, tester, '$tag-initial');
        await _accountTap(tester, find.byTooltip('连接模式'));
        expect(find.text('尚未读取；这里设置登录与后续查询的默认策略。'), findsOneWidget);
        await _accountShot(binding, tester, '$tag-route');
        await _accountTap(tester, find.text('直连'));
        expect(backend.policy, RoutePolicy.direct);
        expect(backend.reads, 0);
        await tester.enterText(
          find.widgetWithText(TextField, '学号'),
          'account-fixture',
        );
        await tester.enterText(
          find.widgetWithText(TextField, '密码'),
          'synthetic-password',
        );
        await tester.pumpAndSettle();
        // 这是原生Flutter输入证据，不代称CUA/物理键盘。
        await _accountShot(binding, tester, '$tag-input');
        await _accountTap(tester, find.byTooltip('显示密码'));
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '密码'))
              .obscureText,
          isFalse,
        );
        await _accountTap(tester, find.byTooltip('隐藏密码'));
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await _accountTap(tester, find.byType(Checkbox).at(1));
        expect(
          tester.widget<Checkbox>(find.byType(Checkbox).first).value,
          isTrue,
        );
        await _accountTap(tester, find.widgetWithText(FilledButton, '登录'));
        expect(backend.loginCalls, 1);
        expect(backend.lastLogin!.autoLogin, isTrue);
        expect(find.byType(UbaaMainShell), findsOneWidget);
      });
    }
    testWidgets('原生登录中保持单次请求 ${brightness.name}', (tester) async {
      final backend = _AccountBackend()..loginGate = Completer<void>();
      await _mountAccount(tester, backend, MemoryCredentialVault(), brightness);
      await tester.enterText(
        find.widgetWithText(TextField, '学号'),
        'account-fixture',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '密码'),
        'synthetic-password',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(backend.loginCalls, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.enabled, isFalse);
      }
      tester
          .widget<TextField>(find.widgetWithText(TextField, '密码'))
          .onSubmitted
          ?.call('synthetic-password');
      expect(backend.loginCalls, 1);
      await _accountShot(
        binding,
        tester,
        'login-${brightness.name}-pending',
        pending: true,
      );
      backend.loginGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(UbaaMainShell), findsOneWidget);
      expect(backend.loginCalls, 1);
    });
  }
}

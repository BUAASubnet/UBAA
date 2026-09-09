part of '../ui_account_test.dart';

/// 独立补图入口，不重跑设置矩阵；原图必须实际包含所声明的资料字段。
void _registerProfileCapture(IntegrationTestWidgetsFlutterBinding binding) {
  for (final brightness in Brightness.values) {
    for (final state in ['normal', 'long', 'missing']) {
      testWidgets('原生账号资料完整视角：${brightness.name}/$state', (tester) async {
        final backend = _AccountBackend(state: state);
        await _mountAccount(
          tester,
          backend,
          MemoryCredentialVault(),
          brightness,
          scale: state == 'long' ? 1.3 : 1,
        );
        await _loginAccount(tester);
        await _openAccountUtility(tester, '我的资料');
        await _accountTap(tester, find.text('查看账号资料'));
        if (state != 'missing') {
          await _accountTap(tester, find.text('显示邮箱'));
          final email = find.text(backend.contactEmail);
          await tester.ensureVisible(email);
          await tester.pumpAndSettle();
          final rect = tester.getRect(email);
          final size = tester.view.physicalSize / tester.view.devicePixelRatio;
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
          await _accountShot(
            binding,
            tester,
            '$state-${brightness.name}-email-visible',
          );
          await _accountTap(tester, find.text('隐藏邮箱'));
          expect(find.text(backend.contactEmail), findsNothing);
          await tester.ensureVisible(find.text('邮箱'));
        } else {
          await tester.ensureVisible(find.text('当前未提供其他资料。'));
        }
        await tester.pumpAndSettle();
        await _accountShot(
          binding,
          tester,
          '$state-${brightness.name}-profile-masked-visible',
        );
      });
    }
  }
}

/// 合成已登录会话直接恢复；不验证真实会话文件或跨进程持久化。
void _registerRestoredAccount(IntegrationTestWidgetsFlutterBinding binding) {
  for (final brightness in Brightness.values) {
    testWidgets('原生合成会话成功恢复无需再次登录：${brightness.name}', (tester) async {
      final backend = _AccountBackend()..signedIn = true;
      await _mountAccount(tester, backend, MemoryCredentialVault(), brightness);
      expect(find.byType(UbaaMainShell), findsOneWidget);
      expect(find.byType(UbaaLoginView), findsNothing);
      expect(backend.lastLogin, isNull);
      final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
      expect(shell.user?.username, 'account-fixture');
      expect(shell.activeRoutes, [ConnectionMode.direct]);
      await _openAccountUtility(tester, '我的资料');
      await _accountTap(tester, find.text('查看账号资料'));
      expect(find.text(backend.contactEmail), findsNothing);
      expect(find.text('合成学校标识'), findsOneWidget);
      await tester.ensureVisible(find.text('合成学校标识'));
      await _accountShot(
        binding,
        tester,
        'restored-${brightness.name}-profile',
      );
      expect(backend.lastLogin, isNull);
    });
  }
}

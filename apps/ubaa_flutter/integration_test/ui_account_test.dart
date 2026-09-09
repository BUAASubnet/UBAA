import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'ui_account/bridge_fixture.dart';
import 'ui_account/bridge_fixture_contract.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_flutter/main.dart';

part 'ui_account/fixture.dart';
part 'ui_account/support.dart';
part 'ui_account/profile_capture.dart';
part 'ui_account/login_old.dart';

void main() {
  if (const bool.fromEnvironment('UBAA_ACCOUNT_INSPECTION')) {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(
      UbaaFlutterApp(
        backend: _AccountBackend(),
        credentialVault: MemoryCredentialVault(
          initial: const Credential(
            username: 'account-fixture',
            password: 'synthetic-password',
            autoLogin: false,
          ),
        ),
      ),
    );
    return;
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('UBAA_ACCOUNT_RESTORE_CAPTURE')) {
    _registerRestoredAccount(binding);
    return;
  }
  if (const bool.fromEnvironment('UBAA_ACCOUNT_PROFILE_CAPTURE')) {
    _registerProfileCapture(binding);
    return;
  }
  registerAccountPartialFixtureContract();
  _registerLoginOld(binding);
  for (final brightness in Brightness.values) {
    for (final state in ['normal', 'long', 'missing']) {
      testWidgets('原生账号资料遮罩与退出：${brightness.name}/$state', (tester) async {
        final backend = _AccountBackend(state: state);
        final vault = MemoryCredentialVault();
        await _mountAccount(
          tester,
          backend,
          vault,
          brightness,
          scale: state == 'long' ? 1.3 : 1,
        );
        await _loginAccount(tester, remember: true);
        expect(vault.hasValue, isTrue);
        final reads = backend.reads;
        await _openAccountUtility(tester, '我的资料');
        expect(find.text(backend.contactEmail), findsNothing);
        await _accountTap(tester, find.text('查看账号资料'));
        if (state == 'missing') {
          expect(find.text('当前未提供其他资料。'), findsOneWidget);
          expect(find.text('显示邮箱'), findsNothing);
        } else {
          expect(find.text('••••••'), findsNWidgets(2));
          await _accountTap(tester, find.text('显示邮箱'));
          expect(find.text(backend.contactEmail), findsOneWidget);
          await _accountTap(tester, find.text('显示手机'));
          expect(find.text('00000000000'), findsOneWidget);
          await _accountShot(
            binding,
            tester,
            '$state-${brightness.name}-revealed',
          );
          await _accountTap(tester, find.text('隐藏邮箱'));
          await _accountTap(tester, find.text('隐藏手机'));
          expect(find.text(backend.contactEmail), findsNothing);
        }
        await _accountShot(binding, tester, '$state-${brightness.name}-masked');
        await _accountTap(tester, find.text('收起账号资料'));
        await _accountTap(tester, find.text('查看账号资料'));
        expect(find.text(backend.contactEmail), findsNothing);
        if (state != 'missing') {
          await _accountTap(tester, find.text('显示邮箱'));
          expect(find.text(backend.contactEmail), findsOneWidget);
        }
        await _accountBack(tester);
        await _openAccountUtility(tester, '我的资料');
        expect(find.text('收起账号资料'), findsNothing);
        expect(backend.reads, reads);
        await _accountTap(tester, find.text('退出登录'));
        expect(find.byType(UbaaLoginView), findsOneWidget);
        expect(backend.logouts, 1);
        expect(vault.hasValue, isTrue);
        await _loginAccount(tester, remember: false);
        expect(backend.lastLogin!.rememberPassword, isFalse);
        expect(backend.lastLogin!.autoLogin, isFalse);
        expect(vault.hasValue, isFalse);
        await _openAccountUtility(tester, '我的资料');
        expect(find.text('收起账号资料'), findsNothing);
        await _accountShot(
          binding,
          tester,
          '$state-${brightness.name}-relogin',
        );
      });
    }
    testWidgets('原生设置主题诊断及清除确认：${brightness.name}', (tester) async {
      final backend = _AccountBackend();
      final vault = MemoryCredentialVault();
      await _mountAccount(tester, backend, vault, brightness);
      await _loginAccount(tester, remember: true, auto: true);
      expect(backend.lastLogin!.rememberPassword, isTrue);
      expect(backend.lastLogin!.autoLogin, isTrue);
      await _openAccountUtility(tester, '设置');
      final reads = backend.reads;
      expect(
        tester.widget<UbaaMainShell>(find.byType(UbaaMainShell)).activeRoutes,
        [ConnectionMode.direct],
      );
      await _accountTap(tester, find.byType(DropdownButton<ThemeMode>));
      await _accountTap(tester, find.text('深色').last);
      expect(
        tester
            .widget<DropdownButton<ThemeMode>>(
              find.byType(DropdownButton<ThemeMode>),
            )
            .value,
        ThemeMode.dark,
      );
      final hostState = tester.state(find.byType(UbaaFlutterApp));
      await tester.pumpWidget(
        UbaaFlutterApp(backend: backend, credentialVault: vault),
      );
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(UbaaFlutterApp)), same(hostState));
      expect(
        tester
            .widget<DropdownButton<ThemeMode>>(
              find.byType(DropdownButton<ThemeMode>),
            )
            .value,
        ThemeMode.dark,
      );
      await _accountBack(tester);
      await _openAccountUtility(tester, '设置');
      expect(
        tester
            .widget<DropdownButton<ThemeMode>>(
              find.byType(DropdownButton<ThemeMode>),
            )
            .value,
        ThemeMode.dark,
      );
      await _accountTap(tester, find.byType(SwitchListTile));
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await _accountTap(tester, find.byType(DropdownButton<RoutePolicy>));
      await _accountTap(tester, find.text('直连').last);
      expect(
        tester
            .widget<DropdownButton<RoutePolicy>>(
              find.byType(DropdownButton<RoutePolicy>),
            )
            .value,
        RoutePolicy.direct,
      );
      expect(backend.reads, reads);
      await _accountTap(tester, find.text('本次运行诊断'));
      final report = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((w) => w.data ?? '')
          .join();
      expect(report, contains('schema_version'));
      expect(report, isNot(contains(backend.contactEmail)));
      expect(report, isNot(contains('account-fixture')));
      await _accountTap(tester, find.text('复制诊断信息'));
      final copied = await Clipboard.getData(Clipboard.kTextPlain);
      expect(copied?.text, report);
      await _accountShot(
        binding,
        tester,
        'normal-${brightness.name}-diagnostics',
      );
      await _accountTap(tester, find.text('关闭'));
      await _accountTap(tester, find.text('退出并清除本机账号'));
      await _accountTap(tester, find.text('取消'));
      expect(vault.hasValue, isTrue);
      expect(backend.logouts, 0);
      await _accountShot(binding, tester, 'normal-${brightness.name}-settings');
      await _accountTap(tester, find.text('退出并清除本机账号'));
      await _accountShot(
        binding,
        tester,
        'normal-${brightness.name}-clear-confirm',
      );
      await _accountTap(tester, find.text('退出并清除'));
      expect(vault.hasValue, isFalse);
      expect(backend.logouts, 1);
      expect(find.byType(UbaaLoginView), findsOneWidget);
      await _accountShot(binding, tester, 'normal-${brightness.name}-cleared');
      await tester.pumpWidget(const SizedBox.shrink());
      await _mountAccount(
        tester,
        _AccountBackend(),
        MemoryCredentialVault(),
        brightness,
      );
      await _loginAccount(tester);
      await _openAccountUtility(tester, '设置');
      expect(
        tester
            .widget<DropdownButton<ThemeMode>>(
              find.byType(DropdownButton<ThemeMode>),
            )
            .value,
        ThemeMode.system,
      );
    });
  }
  testWidgets('原生查询条件折叠不读取并保留草稿', (tester) async {
    final backend = _AccountBackend();
    await _mountAccount(
      tester,
      backend,
      MemoryCredentialVault(),
      Brightness.light,
    );
    await _loginAccount(tester);
    await _accountTap(
      tester,
      find.byType(NavigationRail).evaluate().isNotEmpty
          ? find.descendant(
              of: find.byType(NavigationRail),
              matching: find.byIcon(Icons.apps_outlined),
            )
          : find.byType(NavigationDestination).at(1),
    );
    final card = find.widgetWithText(Card, FeatureId.schedule.title);
    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(card, 200, scrollable: scrollable);
    await _accountTap(tester, card);
    final reads = backend.reads;
    expect(find.byType(TextField), findsNothing);
    await _accountTap(tester, find.byTooltip('搜索与筛选'));
    await _accountTap(tester, find.byType(DropdownButton<FeatureQueryView>));
    await _accountTap(tester, find.text('按输入查询').last);
    final term = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          (w.decoration?.labelText?.startsWith('学期编码') ?? false),
    );
    await tester.enterText(term, '合成未应用草稿');
    await tester.pumpAndSettle();
    final editing = tester.widget<EditableText>(
      find.descendant(of: term, matching: find.byType(EditableText)),
    );
    expect(editing.focusNode.hasFocus, isTrue);
    await _accountTap(tester, find.text('完成'));
    expect(editing.focusNode.hasFocus, isFalse);
    expect(term, findsNothing);
    await _accountShot(binding, tester, 'normal-light-query-collapsed');
    await _accountTap(tester, find.byTooltip('搜索与筛选'));
    expect(tester.widget<TextField>(term).controller!.text, '合成未应用草稿');
    expect(backend.reads, reads);
    await _accountShot(binding, tester, 'normal-light-query-expanded');
  });
  testWidgets('原生保存的合成凭据自动登录失效后清理内存保险箱', (tester) async {
    final backend = _AccountBackend(state: 'invalid-credentials');
    final vault = MemoryCredentialVault(
      initial: const Credential(
        username: 'account-fixture',
        password: 'synthetic-password',
        autoLogin: true,
      ),
    );
    await _mountAccount(tester, backend, vault, Brightness.light);
    expect(backend.lastLogin?.autoLogin, isTrue);
    expect(vault.hasValue, isFalse);
    expect(vault.clearCount, 1);
    expect(backend.reads, 0);
    expect(find.byType(UbaaLoginView), findsOneWidget);
    await _accountShot(binding, tester, 'invalid-auto-login-light');
  });
  testWidgets('原生无安全存储时凭据选项禁用且不冒充持久化', (tester) async {
    final backend = _AccountBackend();
    await _mountAccount(
      tester,
      backend,
      const NoopCredentialVault(),
      Brightness.light,
    );
    for (final box in tester.widgetList<Checkbox>(find.byType(Checkbox))) {
      expect(box.onChanged, isNull);
      expect(box.value, isFalse);
    }
    expect(find.text('当前平台暂未启用安全存储，密码只在本次运行中使用。'), findsOneWidget);
    await _accountShot(binding, tester, 'unavailable-vault-light');
    await _loginAccount(tester);
    expect(backend.lastLogin?.rememberPassword, isFalse);
    expect(backend.lastLogin?.autoLogin, isFalse);
  });
  testWidgets('原生生产适配器处理聚合部分成功而不填充演示业务', (tester) async {
    final client = AccountPartialBridgeClient();
    await _mountAccount(
      tester,
      BridgeBackend(client),
      MemoryCredentialVault(),
      Brightness.light,
    );
    await _loginAccount(tester);
    expect(client.loginCalls, 1);
    expect(
      AccountPartialBridgeClient.outcome.readiness,
      BridgeLoginReadiness.partial,
    );
    expect(AccountPartialBridgeClient.outcome.routes.map((r) => r.state), [
      BridgeRouteLoginState.ready,
      BridgeRouteLoginState.failed,
    ]);
    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    expect(shell.activeRoutes, [ConnectionMode.direct]);
    expect(
      shell.snapshots.values.every(
        (s) => s.status == FeatureLoadStatus.failure,
      ),
      isTrue,
    );
    expect(client.unsupportedReads, greaterThanOrEqualTo(12));
    await _accountShot(binding, tester, 'partial-bridge-light-home');
    await _openAccountUtility(tester, '我的资料');
    expect(find.text('合成部分路线同学'), findsOneWidget);
    await _accountTap(tester, find.text('查看账号资料'));
    expect(find.text('partial@example.invalid'), findsNothing);
    await _accountShot(binding, tester, 'partial-bridge-light-profile');
  });
  testWidgets('原生生产UnavailableBackend保持失败而不进入演示主页', (tester) async {
    await _mountAccount(
      tester,
      const UnavailableBackend(),
      MemoryCredentialVault(),
      Brightness.light,
    );
    expect(find.byType(UbaaMainShell), findsNothing);
    await _loginAccount(tester, succeeds: false);
    expect(find.byType(UbaaLoginView), findsOneWidget);
    await _accountShot(binding, tester, 'unavailable-production-backend-light');
  });
  for (final state in ['login-error', 'restore-error']) {
    testWidgets('原生合成认证边界不进入演示主页：$state', (tester) async {
      final backend = _AccountBackend(state: state);
      await _mountAccount(
        tester,
        backend,
        MemoryCredentialVault(),
        Brightness.light,
      );
      if (state == 'login-error') await _loginAccount(tester, succeeds: false);
      expect(find.byType(UbaaMainShell), findsNothing);
      expect(find.byType(UbaaLoginView), findsOneWidget);
      expect(backend.reads, 0);
      expect(find.text('查看诊断信息'), findsOneWidget);
      await _accountShot(binding, tester, '$state-light');
    });
  }
}

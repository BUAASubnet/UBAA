import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('首页首帧后无需点击即开始恢复，挂起期间三入口仍可用', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final materials = SecureMaterialStore(transport: _Materials());
    await materials.probe();
    final accounts = SecureLocalAccountStore(materials);
    await accounts.retain('fixture-user', retainSession: true);
    final backend = _Backend();
    await tester.pumpWidget(
      UbaaAppHost(backend: backend, localAccountStore: accounts),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(UbaaMainShell), findsOneWidget);
    expect(backend.authCalls, 1);
    expect(find.byTooltip('连接状态'), findsOneWidget);
    expect(find.byType(UbaaSplashView), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('tab-学业')));
    await tester.pump();
    expect(find.byType(UbaaMainShell), findsOneWidget);
    backend.gate.complete(AuthStatus.signedOut);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('完成登录'));
    await tester.pumpAndSettle();
    expect(find.text('记住密码'), findsOneWidget);
    expect(find.text('自动登录'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).at(1), 'fixture-secret');
    await tester.pump();
    final login = find.widgetWithText(FilledButton, '登录');
    await tester.ensureVisible(login);
    await tester.tap(login);
    await tester.pumpAndSettle();
    expect(find.byType(UbaaLoginView), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(find.byType(UbaaMainShell), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('未确认本机账号时安全材料不可用必须显示登录页', (tester) async {
    final accounts = SecureLocalAccountStore(
      SecureMaterialStore(transport: _Materials()),
    );
    final backend = _Backend()..gate.complete(AuthStatus.signedOut);
    await tester.pumpWidget(
      UbaaAppHost(backend: backend, localAccountStore: accounts),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UbaaLoginView), findsOneWidget);
    expect(find.byType(UbaaMainShell), findsNothing);
    expect(backend.authCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Materials implements SecureMaterialTransport {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _Backend extends DemoBackend {
  final gate = Completer<AuthStatus>();
  int authCalls = 0;
  @override
  Future<AuthStatus> authStatus() {
    authCalls++;
    return gate.future;
  }

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'fixture-user');
}

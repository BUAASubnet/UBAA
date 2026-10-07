import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  for (final background in [
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.detached,
  ]) {
    testWidgets('${background.name} 返回前台复用 backend 和当前入口，仅做一次恢复', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = _Backend();
      var created = 0;
      await tester.pumpWidget(
        UbaaAppHost(
          backendFactory: () {
            created++;
            return backend;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('tab-普通功能')));
      await tester.pumpAndSettle();
      await cycle(tester, background);
      await tester.pumpAndSettle();
      expect(created, 1);
      expect(backend.disposed, 0);
      expect(backend.authCalls, 2);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(backend.authCalls, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(backend.disposed, 1);
    });
  }
  testWidgets('进行中的恢复合并多次前后台切换，不结束后再重建或重复检查', (tester) async {
    final backend = _Backend();
    await tester.pumpWidget(UbaaAppHost(backend: backend));
    await tester.pumpAndSettle();
    backend.authGate = Completer<void>();
    await cycle(tester, AppLifecycleState.paused);
    expect(backend.authCalls, 2);
    await cycle(tester, AppLifecycleState.paused);
    expect(backend.authCalls, 2);
    backend.authGate!.complete();
    await tester.pumpAndSettle();
    expect(backend.authCalls, 2);
    expect(backend.disposed, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('初始化挂起期间返回前台，初始化完成后复用原实例恢复', (tester) async {
    final backend = _Backend()..authGate = Completer<void>();
    var created = 0;
    await tester.pumpWidget(
      UbaaAppHost(
        backendFactory: () {
          created++;
          return backend;
        },
      ),
    );
    await tester.pump();
    await cycle(tester, AppLifecycleState.paused);
    expect(backend.authCalls, 1);
    backend.authGate!.complete();
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(backend.authCalls, 2);
    expect(backend.disposed, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('登录挂起期间返回前台，完成后恢复但不丢当前实例', (tester) async {
    final backend = _Backend()
      ..signedIn = false
      ..loginGate = Completer<void>();
    await tester.pumpWidget(UbaaAppHost(backend: backend));
    await tester.pumpAndSettle();
    final view = tester.widget<UbaaLoginView>(find.byType(UbaaLoginView));
    view.onUsernameChanged('fixture-user');
    view.onPasswordChanged('synthetic-password');
    view.onSubmit();
    await tester.pump();
    await cycle(tester, AppLifecycleState.paused);
    expect(backend.authCalls, 1);
    backend.loginGate!.complete();
    await tester.pumpAndSettle();
    expect(backend.authCalls, 2);
    expect(find.byType(UbaaMainShell), findsOneWidget);
    expect(backend.disposed, 0);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> cycle(WidgetTester tester, AppLifecycleState background) async {
  final states = <AppLifecycleState>[
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    if (background != AppLifecycleState.hidden) AppLifecycleState.paused,
    if (background == AppLifecycleState.detached) AppLifecycleState.detached,
    if (background != AppLifecycleState.detached) ...[
      if (background == AppLifecycleState.paused) AppLifecycleState.hidden,
      AppLifecycleState.inactive,
    ],
    AppLifecycleState.resumed,
  ];
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

class _Backend implements UbaaBackend, BackendLifecycle {
  int disposed = 0, authCalls = 0;
  bool signedIn = true;
  Completer<void>? authGate, loginGate;
  @override
  Future<AuthStatus> authStatus() async {
    authCalls++;
    await authGate?.future;
    return signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;
  }

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'fixture-user');
  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}
  @override
  Future<void> login(LoginInput input) async {
    await loginGate?.future;
    signedIn = true;
  }

  @override
  Future<void> logout() async {
    signedIn = false;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();
  @override
  Future<void> dispose() async {
    disposed++;
  }
}

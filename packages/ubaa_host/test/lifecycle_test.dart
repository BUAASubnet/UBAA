import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('显式 backend 不调用工厂且恢复时不替换', (tester) async {
    final backend = _LifecycleBackend();
    var factoryCalls = 0;

    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        backendFactory: () {
          factoryCalls++;
          return _LifecycleBackend();
        },
      ),
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(factoryCalls, 0);
    expect(backend.disposeCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(backend.disposeCalls, 1);
  });

  for (final backgroundState in <AppLifecycleState>[
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets('${backgroundState.name} 后首次 resumed 只重建一次并单次释放', (
      tester,
    ) async {
      final backends = <_LifecycleBackend>[];
      var factoryCalls = 0;

      await tester.pumpWidget(
        UbaaAppHost(
          backendFactory: () {
            factoryCalls++;
            final backend = _LifecycleBackend();
            backends.add(backend);
            return backend;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(factoryCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(backgroundState);
      await tester.pump();
      if (backgroundState == AppLifecycleState.paused) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(factoryCalls, 2);
      expect(backends[0].disposeCalls, 1);
      expect(backends[1].disposeCalls, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(factoryCalls, 2);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(backends.map((backend) => backend.disposeCalls), <int>[1, 1]);
    });
  }

  testWidgets('初始化繁忙期间的 resumed 请求会在初始化完成后重建', (tester) async {
    final first = _DelayedLifecycleBackend();
    final replacement = _LifecycleBackend();
    var factoryCalls = 0;

    await tester.pumpWidget(
      UbaaAppHost(
        backendFactory: () {
          factoryCalls++;
          return factoryCalls == 1 ? first : replacement;
        },
      ),
    );
    await first.authStarted.future;
    expect(factoryCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(factoryCalls, 1);

    first.releaseAuth.complete();
    await tester.pumpAndSettle();

    expect(factoryCalls, 2);
    expect(first.disposeCalls, 1);
    expect(replacement.disposeCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(replacement.disposeCalls, 1);
  });

  testWidgets('登录繁忙期间的 resumed 请求会在登录完成后重建', (tester) async {
    final first = _DelayedLoginLifecycleBackend();
    final replacement = _LifecycleBackend();
    var factoryCalls = 0;

    await tester.pumpWidget(
      UbaaAppHost(
        backendFactory: () {
          factoryCalls++;
          return factoryCalls == 1 ? first : replacement;
        },
      ),
    );
    await tester.pumpAndSettle();

    final login = tester.widget<UbaaLoginView>(find.byType(UbaaLoginView));
    login.onUsernameChanged('student-fixture');
    login.onPasswordChanged('fixture-password');
    login.onSubmit();
    await first.loginStarted.future;

    await _backgroundAndResume(tester);
    expect(factoryCalls, 1);

    first.releaseLogin.complete();
    await tester.pumpAndSettle();

    expect(factoryCalls, 2);
    expect(first.disposeCalls, 1);
    expect(replacement.disposeCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(replacement.disposeCalls, 1);
  });

  testWidgets('重建过程中发生的新后台周期会在前次完成后再次重建', (tester) async {
    final first = _BlockingDisposeBackend();
    final second = _LifecycleBackend();
    final third = _LifecycleBackend();
    final backends = <_LifecycleBackend>[first, second, third];
    var factoryCalls = 0;

    await tester.pumpWidget(
      UbaaAppHost(backendFactory: () => backends[factoryCalls++]),
    );
    await tester.pumpAndSettle();

    await _backgroundAndResume(tester);
    await first.disposeStarted.future;
    expect(factoryCalls, 2);

    await _backgroundAndResume(tester);
    expect(factoryCalls, 2);

    first.releaseDispose.complete();
    await tester.pumpAndSettle();

    expect(factoryCalls, 3);
    expect(first.disposeCalls, 1);
    expect(second.disposeCalls, 1);
    expect(third.disposeCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(third.disposeCalls, 1);
  });
}

Future<void> _backgroundAndResume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

class _LifecycleBackend implements UbaaBackend, BackendLifecycle {
  int disposeCalls = 0;

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async => null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      const FeatureResult.empty();

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

final class _DelayedLifecycleBackend extends _LifecycleBackend {
  final Completer<void> authStarted = Completer<void>();
  final Completer<void> releaseAuth = Completer<void>();

  @override
  Future<AuthStatus> authStatus() async {
    authStarted.complete();
    await releaseAuth.future;
    return AuthStatus.signedOut;
  }
}

final class _BlockingDisposeBackend extends _LifecycleBackend {
  final Completer<void> disposeStarted = Completer<void>();
  final Completer<void> releaseDispose = Completer<void>();

  @override
  Future<void> dispose() async {
    disposeCalls++;
    disposeStarted.complete();
    await releaseDispose.future;
  }
}

final class _DelayedLoginLifecycleBackend extends _LifecycleBackend {
  final Completer<void> loginStarted = Completer<void>();
  final Completer<void> releaseLogin = Completer<void>();

  @override
  Future<void> login(LoginInput input) async {
    loginStarted.complete();
    await releaseLogin.future;
  }

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'student-fixture');
}

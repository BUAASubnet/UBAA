import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_test_support/recovery.dart' as fixtures;

void main() {
  testWidgets('后端打开期间进入后台，迟到实例等待窗口可见才订阅和恢复', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final events = StreamController<void>.broadcast();
    final opened = Completer<UbaaBackend>();
    final backend = fixtures.FakeRecoveryBackend();
    await tester.pumpWidget(
      UbaaAppHost(
        backendFactory: () => opened.future,
        localAccountStore: await fixtures.savedAccounts(),
        networkChanges: events.stream,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    opened.complete(backend);
    await tester.pump();
    await tester.pump();
    expect(events.hasListener, isFalse);
    expect(backend.authCalls, 0);
    expect(backend.readCalls, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(events.hasListener, isTrue);
    expect(backend.authCalls, 1);
    expect(backend.readCalls, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(backend.authCalls, 1);
    await tester.pumpWidget(const SizedBox());
    await events.close();
  });

  testWidgets('本地首页首帧前的恢复事件与启动恢复合并', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final opened = Completer<UbaaBackend>();
    final backend = fixtures.FakeRecoveryBackend();
    await tester.pumpWidget(
      UbaaAppHost(
        backendFactory: () => opened.future,
        localAccountStore: await fixtures.savedAccounts(),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    opened.complete(backend);
    await tester.pumpAndSettle();
    expect(backend.authCalls, 1);
    expect(backend.loginCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  for (final hidden in [AppLifecycleState.hidden, AppLifecycleState.paused]) {
    testWidgets('$hidden 后窗口可见但未获焦点，恢复订阅与读取且获焦点不重复恢复', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<void>.broadcast();
      final backend = fixtures.FakeRecoveryBackend();
      await tester.pumpWidget(
        UbaaAppHost(
          backend: backend,
          localAccountStore: await fixtures.savedAccounts(),
          networkChanges: events.stream,
        ),
      );
      await tester.pumpAndSettle();
      expect(backend.authCalls, 1);
      final reads = backend.readCalls;
      tester.binding.handleAppLifecycleStateChanged(hidden);
      // 原生隐藏状态停止帧回调；这里只等待取消订阅的微任务。
      await Future<void>.microtask(() {});
      expect(events.hasListener, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(events.hasListener, isTrue);
      expect(backend.authCalls, 2);
      expect(backend.readCalls, greaterThan(reads));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(backend.authCalls, 2);
      expect(backend.loginCalls, 0);
      await tester.pumpWidget(const SizedBox());
      expect(events.hasListener, isFalse);
      await events.close();
    });
  }

  testWidgets('仅窗口焦点变化不重启恢复，在途恢复跨隐藏与重新可见仍合并', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final backend = fixtures.FakeRecoveryBackend();
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        localAccountStore: await fixtures.savedAccounts(),
      ),
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(backend.authCalls, 1);
    backend.gate = Completer<AuthStatus>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(backend.authCalls, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(backend.authCalls, 2);
    backend.gate!.complete(AuthStatus.signedIn);
    await tester.pumpAndSettle();
    expect(backend.authCalls, 2);
    expect(backend.loginCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });
}

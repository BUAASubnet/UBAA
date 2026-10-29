import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_test_support/recovery.dart' as fixtures;

void main() {
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

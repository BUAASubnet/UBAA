import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_test_support/recovery.dart' as fixtures;

void main() {
  testWidgets('宿主网络提示唤醒失败恢复，后台停订阅，销毁后不再回调', (tester) async {
    final events = StreamController<void>.broadcast();
    final backend = fixtures.FakeRecoveryBackend()
      ..authError = const BackendException(UbaaErrorCode.networkError);
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        localAccountStore: await fixtures.savedAccounts(),
        networkChanges: events.stream,
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.authCalls, 1);
    expect(events.hasListener, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(events.hasListener, isFalse);
    backend.authError = null;
    events.add(null);
    await tester.pump(const Duration(minutes: 1));
    expect(backend.authCalls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(backend.authCalls, 2);
    expect(events.hasListener, isTrue);
    backend.authError = const BackendException(UbaaErrorCode.networkError);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(backend.authCalls, 3);
    backend.authError = null;
    events.add(null);
    events.add(null);
    await tester.pumpAndSettle();
    expect(backend.authCalls, 4);
    expect(backend.loginCalls, 0);
    expect(backend.readCalls, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(events.hasListener, isFalse);
    events.add(null);
    await tester.pump(const Duration(minutes: 10));
    expect(backend.authCalls, 4);
    await events.close();
  });
}

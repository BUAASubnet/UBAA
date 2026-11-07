import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_test_support/recovery.dart' as fixtures;
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('单项目标恢复期间宿主保持非连接状态并提供待办投影', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final accounts = await fixtures.widgetAccounts(tester);
    final backend = _HomeTargetBackend();
    addTearDown(() {
      if (!backend.releaseSchedule.isCompleted)
        backend.releaseSchedule.complete();
      if (!backend.releaseSpoc.isCompleted) backend.releaseSpoc.complete();
    });
    await tester.pumpWidget(
      UbaaAppHost(backend: backend, localAccountStore: accounts),
    );
    await accounts.settle(tester);
    Future<void> pumpUntil(bool Function() completed) async {
      for (var frame = 0; frame < 100 && !completed(); frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(completed(), isTrue, reason: '恢复未到达预期阶段');
      await tester.pump();
    }

    await pumpUntil(() => backend.scheduleStarted.isCompleted);
    expect(
      tester.widget<UbaaMainShell>(find.byType(UbaaMainShell)).connecting,
      isTrue,
    );
    backend.releaseSchedule.complete();
    await pumpUntil(() => backend.spocStarted.isCompleted);

    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    expect(shell.connecting, isFalse);
    expect(shell.homeState, isNotNull);

    backend.releaseSpoc.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('后端打开期间进入后台，迟到实例等待窗口可见才订阅和恢复', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final events = StreamController<void>.broadcast();
    final opened = Completer<UbaaBackend>();
    final accounts = await fixtures.widgetAccounts(tester);
    final backend = fixtures.FakeRecoveryBackend();
    await tester.pumpWidget(
      UbaaAppHost(
        backendFactory: () => opened.future,
        localAccountStore: accounts,
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
    await accounts.settle(tester);
    await tester.pumpAndSettle();
    expect(events.hasListener, isTrue);
    expect(backend.authCalls, 1);
    expect(backend.readCalls, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await accounts.settle(tester);
    await tester.pumpAndSettle();
    expect(backend.authCalls, 1);
    await tester.pumpWidget(const SizedBox());
    await events.close();
  });

  testWidgets('本地首页首帧前的恢复事件与启动恢复合并', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final opened = Completer<UbaaBackend>();
    final accounts = await fixtures.widgetAccounts(tester);
    final backend = fixtures.FakeRecoveryBackend();
    await tester.pumpWidget(
      UbaaAppHost(
        backendFactory: () => opened.future,
        localAccountStore: accounts,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    opened.complete(backend);
    await accounts.settle(tester);
    await tester.pumpAndSettle();
    expect(backend.authCalls, 1);
    expect(backend.loginCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  for (final hidden in [AppLifecycleState.hidden, AppLifecycleState.paused]) {
    testWidgets('$hidden 后窗口可见但未获焦点，恢复订阅与读取且获焦点不重复恢复', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<void>.broadcast();
      final accounts = await fixtures.widgetAccounts(tester);
      final backend = fixtures.FakeRecoveryBackend();
      await tester.pumpWidget(
        UbaaAppHost(
          backend: backend,
          localAccountStore: accounts,
          networkChanges: events.stream,
        ),
      );
      await accounts.settle(tester);
      await tester.pumpAndSettle();
      expect(backend.authCalls, 1);
      final reads = backend.readCalls;
      tester.binding.handleAppLifecycleStateChanged(hidden);
      // 原生隐藏状态停止帧回调；这里只等待取消订阅的微任务。
      await Future<void>.microtask(() {});
      expect(events.hasListener, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await accounts.settle(tester);
      await tester.pumpAndSettle();
      expect(events.hasListener, isTrue);
      expect(backend.authCalls, 2);
      expect(backend.readCalls, greaterThan(reads));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await accounts.settle(tester);
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
    final accounts = await fixtures.widgetAccounts(tester);
    final backend = fixtures.FakeRecoveryBackend();
    await tester.pumpWidget(
      UbaaAppHost(backend: backend, localAccountStore: accounts),
    );
    await accounts.settle(tester);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await accounts.settle(tester);
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
    await accounts.settle(tester);
    await tester.pumpAndSettle();
    expect(backend.authCalls, 2);
    expect(backend.loginCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });
}

class _HomeTargetBackend extends fixtures.FakeRecoveryBackend
    implements RequiredSessionBackend, ProgressiveReadBackend, HomeTodoBackend {
  final scheduleStarted = Completer<void>();
  final releaseSchedule = Completer<void>();
  final spocStarted = Completer<void>();
  final releaseSpoc = Completer<void>();

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    if (feature == FeatureId.schedule) {
      if (!scheduleStarted.isCompleted) scheduleStarted.complete();
      await releaseSchedule.future;
    }
    if (feature == FeatureId.spoc) {
      if (!spocStarted.isCompleted) spocStarted.complete();
      await releaseSpoc.future;
    }
    return const RecoveredRouteSession(
      route: ConnectionMode.direct,
      profile: UserSummary(username: 'fixture-user'),
    );
  }

  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) async => RecoveredRouteSession(
    route: route,
    profile: const UserSummary(username: 'fixture-user'),
  );

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      FeatureResult.success(summary: feature.name);

  @override
  Future<HomeTodoProjection> projectHomeTodos(HomeTodoRequest request) async =>
      HomeTodoProjection(const []);
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';

void main() {
  testWidgets('打开后端期间可以绘制且销毁后释放迟到实例', (tester) async {
    final gate = Completer<UbaaBackend>();
    await tester.pumpWidget(UbaaAppHost(backendFactory: () => gate.future));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('正在打开本地数据…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final lateBackend = _Backend();
    gate.complete(lateBackend);
    await tester.pump();
    expect(lateBackend.disposals, 1);
    expect(lateBackend.authCalls, 0);
  });

  for (final failure in InitializationFailure.values) {
    testWidgets('初始化分类 ${failure.name} 安全展示并可重新打开', (tester) async {
      var attempts = 0;
      final backend = _Backend();
      await tester.pumpWidget(
        UbaaAppHost(
          backendFactory: () async {
            attempts++;
            return attempts == 1
                ? UnavailableBackend(failure: failure)
                : backend;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('重新打开'), findsOneWidget);
      expect(find.textContaining('诊断编号：UBAA-'), findsOneWidget);
      await tester.tap(find.text('重新打开'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(backend.authCalls, 1);
      expect(find.text('重新打开'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('工厂失败后显示脱敏故障与重新打开入口', (tester) async {
    await tester.pumpWidget(
      UbaaAppHost(
        backendFactory: () => throw StateError('/private/secret=fixture'),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('重新打开'), findsOneWidget);
    expect(find.textContaining('/private'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

class _Backend extends DemoBackend implements BackendLifecycle {
  int disposals = 0;
  int authCalls = 0;
  @override
  Future<AuthStatus> authStatus() async {
    authCalls++;
    return AuthStatus.signedOut;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';

void main() {
  testWidgets('个人页可查看本次运行诊断且不会包含账号资料', (tester) async {
    await tester.pumpWidget(UbaaAppHost(backend: _SignedInBackend()));
    await tester.pumpAndSettle();
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Drawer), matching: find.text('设置')),
    );
    await tester.pumpAndSettle();
    expect(find.text('本次运行诊断'), findsOneWidget);
    await tester.tap(find.text('本次运行诊断'));
    await tester.pumpAndSettle();
    final report = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((text) => text.data ?? '')
        .join();
    expect(report, contains('schema_version'));
    expect(report, isNot(contains('fixture-private-name')));
    expect(report, isNot(contains('fixture-private-account')));
  });
  testWidgets('初始化失败时未登录用户也能主动复制本地排障报告', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData')
          copied = (call.arguments as Map)['text'] as String;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(UbaaAppHost(backend: _FailingInitialization()));
    await tester.pumpAndSettle();
    expect(find.text('查看诊断信息'), findsOneWidget);
    await tester.tap(find.text('查看诊断信息'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制诊断信息'));
    await tester.pumpAndSettle();
    expect(copied, contains('initialization'));
    expect(copied, contains('internal_error'));
    expect(copied, contains('UBAA-'));
    expect(copied, isNot(contains('模拟原始个人数据')));
    expect(tester.takeException(), isNull);
  });
}

class _FailingInitialization extends DemoBackend {
  @override
  Future<AuthStatus> authStatus() async => throw StateError('模拟原始个人数据');
}

class _SignedInBackend extends DemoBackend {
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;

  @override
  Future<UserSummary?> userInfo() async => const UserSummary(
    username: 'fixture-private-account',
    displayName: 'fixture-private-name',
  );
}

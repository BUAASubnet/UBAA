import 'dart:async';

import 'package:ubaa_ui/src/app/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  testWidgets('诊断版本读取未完成时可关闭宿主且不遗留定时器', (tester) async {
    await tester.pumpWidget(
      UbaaAppHost(
        backend: DemoBackend(),
        appInformation: _PendingAppInformation(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('个人页可查看诊断信息且不会包含账号资料', (tester) async {
    await tester.pumpWidget(UbaaAppHost(backend: _SignedInBackend()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('诊断信息'),
      250,
      scrollable: find.descendant(
        of: find.byType(ProfileView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('诊断信息'), findsOneWidget);
    await tester.ensureVisible(find.text('诊断信息'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('诊断信息'));
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

class _PendingAppInformation implements PlatformAppInformation {
  final _version = Completer<String?>();

  @override
  Future<String?> version() => _version.future;

  @override
  Future<bool> open(AppLink link) async => false;
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

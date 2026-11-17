import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ubaa_ui/src/app/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../support/host/fakes.dart' show fixtureCapabilities;

void main() {
  testWidgets('设置分享完整诊断保留学校原文且不自动打开反馈', (tester) async {
    const channel = MethodChannel('cn.edu.buaa.ubaa/agenda-file');
    Map? shared;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'shareReport') shared = call.arguments as Map;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final backend = _RawDiagnosticBackend();
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        diagnosticReportExporter: const DiagnosticReportExporter(
          operatingSystem: 'android',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.exports, 0);
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
    await tester.ensureVisible(find.text('诊断信息'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('诊断信息'));
    await tester.pumpAndSettle();
    expect(backend.exports, 0);
    await tester.tap(find.text('分享完整诊断'));
    await tester.pumpAndSettle();
    expect(backend.exports, 1);
    final report =
        jsonDecode(utf8.decode((shared!['bytes'] as List).cast<int>())) as Map;
    expect(report['schema_version'], 4);
    expect(report['contains_sensitive_data'], true);
    expect(
      report['raw_http']['records'][0]['response']['body'],
      'fixture-private-token',
    );
  });

  testWidgets('后端创建失败可分享对应报告，保留阶段、原始原因与构建版本', (tester) async {
    const channel = MethodChannel('cn.edu.buaa.ubaa/agenda-file');
    Map? shared;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'shareReport') shared = call.arguments as Map;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final appInformation = _PendingAppInformation();
    await tester.pumpWidget(
      UbaaAppHost(
        appInformation: appInformation,
        diagnosticReportExporter: const DiagnosticReportExporter(
          operatingSystem: 'android',
        ),
        backendFactory: () => throw TimeoutException('模拟超时'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看诊断信息'));
    await tester.pumpAndSettle();
    appInformation.completeVersion('2.0.1+2100');
    await tester.pump();
    await tester.tap(find.text('分享报告文件'));
    await tester.pumpAndSettle();
    expect(shared, isNotNull);
    final report =
        jsonDecode(utf8.decode((shared!['bytes'] as List).cast<int>()))
            as Map<String, dynamic>;
    final event = (report['events'] as List).single as Map<String, dynamic>;
    expect(event['operation'], 'initialization');
    expect(event['cause'], 'timeout');
    expect(event['initialization_stage'], 'backendOpen');
    expect(report['platform'], Platform.operatingSystem);
    expect(report['app_version'], '2.0.1+2100');
    expect(shared!['name'], endsWith('.json'));
    expect(appInformation.opened, isEmpty);
    await tester.tap(find.text('打开反馈页面'));
    await tester.pumpAndSettle();
    expect(appInformation.opened, [AppLink.feedback]);
  });

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

  testWidgets('SDK 启动失败在重启后仍可读取，保留旧版本与平台', (tester) async {
    final preferences = MemoryPreferenceValues();
    final oldInformation = _PendingAppInformation()
      ..completeVersion('2.0.1+2100');
    final oldFailure = FormatException('模拟 SDK 故障');
    Widget? launched;
    await expectLater(
      bootstrapUbaaHost(
        ensureFlutterInitialized: () {},
        initializeSdk: () async => throw oldFailure,
        debugHello: () => 'UBAA FRB 2.13.0 ready',
        createCapabilities: () async => fixtureCapabilities(),
        runApplication: (app) => launched = app,
        preferenceValues: preferences,
        appInformation: oldInformation,
      ),
      throwsA(same(oldFailure)),
    );
    await tester.pumpWidget(launched!);
    final issue = tester
        .widget<EditableText>(find.textContaining('诊断编号：UBAA-'))
        .controller
        .text
        .split('：')
        .last;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      UbaaAppHost(
        preferenceValues: preferences,
        appInformation: _PendingAppInformation()..completeVersion('2.0.2+2110'),
        backendFactory: () => throw StateError('模拟后端故障'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看诊断历史'));
    await tester.pumpAndSettle();
    final text = tester.widget<EditableText>(
      find.textContaining('"previous_events"'),
    );
    final report = jsonDecode(text.controller.text) as Map<String, dynamic>;
    final previous = (report['previous_events'] as List).single as Map;
    expect(previous['issue_id'], issue);
    expect(previous['cause'], 'format');
    expect(previous['initialization_stage'], 'sdk');
    expect(previous['app_version'], '2.0.1+2100');
    expect(previous['platform'], Platform.operatingSystem);
    expect(report['app_version'], '2.0.2+2110');
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
    expect(copied, contains('sessionState'));
    expect(copied, contains('UBAA-'));
    expect(copied, isNot(contains('模拟原始个人数据')));
    expect(tester.takeException(), isNull);
  });
}

class _PendingAppInformation implements PlatformAppInformation {
  final _version = Completer<String?>();
  final opened = <AppLink>[];

  void completeVersion(String version) => _version.complete(version);

  @override
  Future<String?> version() => _version.future;

  @override
  Future<bool> open(AppLink link) async {
    opened.add(link);
    return true;
  }
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

class _RawDiagnosticBackend extends _SignedInBackend
    implements RawDiagnosticsBackend {
  int exports = 0;
  @override
  String exportRawDiagnostics() {
    exports++;
    return '{"records":[{"response":{"body":"fixture-private-token"}}]}';
  }
}

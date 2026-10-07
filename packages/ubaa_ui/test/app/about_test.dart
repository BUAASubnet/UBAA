import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('旧侧栏关于入口保留单标题与项目反馈链接', (tester) async {
    await _mount(tester);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('关于'), findsOneWidget);
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('UBAA 应用'), findsOneWidget);
    expect(find.text('开源项目 (GitHub)'), findsOneWidget);
    expect(find.text('反馈建议 (Issues)'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    final card = find.ancestor(
      of: find.text('UBAA 应用'),
      matching: find.byType(Card),
    );
    expect(
      tester.getTopLeft(card).dy - tester.getBottomLeft(find.byType(AppBar)).dy,
      lessThanOrEqualTo(20),
      reason: '旧版说明卡紧随顶栏，不能被共享居中容器推到半屏',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('关于显示安装包版本并只打开旧版公开目的地', (tester) async {
    final links = <AppLink>[];
    await _mount(
      tester,
      version: () async => '2.3.4+17',
      open: (link) async {
        links.add(link);
        return true;
      },
    );
    await _open(tester);
    expect(find.text('版本：2.3.4+17'), findsOneWidget);
    for (final link in AppLink.values) {
      await tester.ensureVisible(find.text(link.label));
      await tester.tap(find.text(link.label));
      await tester.pumpAndSettle();
    }
    expect(links, AppLink.values);
    expect(find.text('链接未能打开'), findsNothing);
  });

  testWidgets('关于版本读取失败可重试且外链失败可复制准确地址', (tester) async {
    var calls = 0;
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData')
          clipboard = (call.arguments as Map)['text'] as String;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _mount(
      tester,
      version: () async {
        if (++calls == 1) throw StateError('不可输出原始错误');
        return '2.3.4+18';
      },
      open: (_) async => false,
    );
    await _open(tester);
    expect(find.text('版本信息暂不可用'), findsOneWidget);
    expect(find.textContaining('不可输出原始错误'), findsNothing);
    await tester.tap(find.text('重新读取版本'));
    await tester.pumpAndSettle();
    expect(find.text('版本：2.3.4+18'), findsOneWidget);
    await tester.ensureVisible(find.text(AppLink.feedback.label));
    await tester.tap(find.text(AppLink.feedback.label));
    await tester.pumpAndSettle();
    expect(find.text(AppLink.feedback.url), findsOneWidget);
    await tester.tap(find.text('复制地址'));
    await tester.pumpAndSettle();
    expect(clipboard, 'https://github.com/BUAASubnet/UBAA/issues');
  });

  testWidgets('关于离开后迟到外链失败不弹回旧页且在途不重复打开', (tester) async {
    final pending = Completer<bool>();
    var calls = 0;
    await _mount(
      tester,
      open: (_) {
        calls++;
        return pending.future;
      },
    );
    await _open(tester);
    await tester.ensureVisible(find.text(AppLink.project.label));
    await tester.tap(find.text(AppLink.project.label));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, AppLink.project.label),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('链接未能打开'), findsNothing);
    expect(find.text('关于'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _mount(
  WidgetTester tester, {
  Future<String?> Function()? version,
  Future<bool> Function(AppLink)? open,
}) => tester.pumpWidget(
  MaterialApp(
    theme: UbaaTheme.light(),
    home: UbaaMainShell(
      user: const UserSummary(username: 'synthetic'),
      snapshots: {
        for (final feature in FeatureId.values)
          feature: FeatureSnapshot(
            feature: feature,
            status: FeatureLoadStatus.empty,
          ),
      },
      routePolicy: RoutePolicy.auto,
      telemetryEnabled: false,
      onRefresh: () async {},
      onRetryFeature: (_) async {},
      onLogout: () async {},
      onLogoutAndClearAccount: () async {},
      onRoutePolicyChanged: (_) {},
      onTelemetryChanged: (_) {},
      onLoadAppVersion: version,
      onOpenAppLink: open,
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('关于'));
  await tester.pumpAndSettle();
}

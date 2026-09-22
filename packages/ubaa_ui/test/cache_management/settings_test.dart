import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart';

void main() {
  testWidgets('用量尚未返回时清理失败不能显示内容已清除', (tester) async {
    final usage = Completer<CacheUsageSummary>();
    await mount(
      tester,
      onRead: (_) => usage.future,
      onClear: (_) async => throw StateError('合成清除失败'),
    );
    await tap(tester, '清理缓存');
    await tap(tester, '确认清理');
    expect(find.text('缓存未能清除，请稍后重试。'), findsOneWidget);
    expect(find.text('内容已清除'), findsNothing);
    usage.completeError(StateError('合成用量失败'));
    await tester.pumpAndSettle();
  });
  testWidgets('设置显示数值用量，清理需本地确认且维护失败单列', (tester) async {
    var calls = 0;
    await mount(
      tester,
      onClear: (id) async {
        expect(id, 'a');
        calls++;
        return const CacheClearOutcome(
          compacted: false,
          maintenanceError: CacheMaintenanceFailure.capacity,
        );
      },
    );
    expect(find.textContaining('1 条'), findsOneWidget);
    expect(find.textContaining('内容 1.0 KB'), findsOneWidget);
    await tap(tester, '清理缓存');
    expect(find.text('清理本机缓存？'), findsOneWidget);
    expect(calls, 0);
    await tap(tester, '取消');
    expect(calls, 0);
    await tap(tester, '清理缓存');
    await tap(tester, '确认清理');
    expect(calls, 1);
    expect(find.text('内容已清除，空间回收暂未完成。'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
  });
  testWidgets('事务失败不显示成功且保留重试入口', (tester) async {
    await mount(tester, onClear: (_) async => throw StateError('合成失败'));
    await tap(tester, '清理缓存');
    await tap(tester, '确认清理');
    expect(find.text('缓存未能清除，请稍后重试。'), findsOneWidget);
    expect(find.text('缓存已清除。'), findsNothing);
    expect(find.text('清理缓存'), findsOneWidget);
  });
  testWidgets('清理执行中不能重复点击', (tester) async {
    final gate = Completer<CacheClearOutcome>();
    var calls = 0;
    await mount(
      tester,
      onClear: (_) {
        calls++;
        return gate.future;
      },
    );
    await tap(tester, '清理缓存');
    await tester.tap(find.text('确认清理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('正在清理…'), findsOneWidget);
    expect(calls, 1);
    gate.complete(const CacheClearOutcome(compacted: true));
    await tester.pumpAndSettle();
    expect(find.text('缓存已清除。'), findsOneWidget);
  });
  testWidgets('确认期间切换账号，旧确认不调用新账号清理', (tester) async {
    final account = ValueNotifier('a');
    addTearDown(account.dispose);
    var calls = 0;
    await mount(
      tester,
      account: account,
      onClear: (_) async {
        calls++;
        return const CacheClearOutcome(compacted: true);
      },
    );
    await tap(tester, '清理缓存');
    account.value = 'b';
    await tester.pumpAndSettle();
    await tap(tester, '确认清理');
    expect(calls, 0);
  });
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> mount(
  WidgetTester tester, {
  ValueNotifier<String>? account,
  Future<CacheUsageSummary> Function(String)? onRead,
  required Future<CacheClearOutcome> Function(String) onClear,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1100);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final owner = account ?? ValueNotifier('a');
  if (account == null) addTearDown(owner.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: ValueListenableBuilder<String>(
        valueListenable: owner,
        builder: (_, id, _) => UbaaMainShell(
          user: UserSummary(username: id),
          snapshots: {
            for (final f in FeatureId.values) f: FeatureSnapshot(feature: f),
          },
          routePolicy: RoutePolicy.direct,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
          cacheAccountId: id,
          onReadCacheUsage:
              onRead ??
              (id) async => CacheUsageSummary(
                accountId: id,
                entryCount: 1,
                contentBytes: 1024,
                databaseBytes: 4096,
                reusableBytes: 0,
                softLimitBytes: 50 * 1024 * 1024,
                hardLimitBytes: 100 * 1024 * 1024,
              ),
          onClearBusinessCache: onClear,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await openUtility(tester, '设置');
}

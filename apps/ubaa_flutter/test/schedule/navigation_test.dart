import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../integration_test/ui_schedule_navigation/backend.dart';

void main() {
  testWidgets('大字长周名称不被本周标记挤成窄列', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final backend = ScheduleNavigationBackend(state: 'long');
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
        initialTab: 1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Card, FeatureId.schedule.title));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索与筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '选择教学周'));
    await tester.pumpAndSettle();
    Finder option(int n) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(backend.title('合成教学第$n周')),
    );
    expect(
      tester.getSize(option(4)).width,
      greaterThanOrEqualTo(tester.getSize(option(3)).width - 48),
    );
  });
  testWidgets('周选项失败后重新获取可以恢复列表且不发课程查询', (tester) async {
    final backend = ScheduleNavigationBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
        initialTab: 1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Card, FeatureId.schedule.title));
    await tester.pumpAndSettle();
    backend.failOptions = FeatureQueryView.scheduleWeeks;
    await tester.tap(find.byTooltip('搜索与筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '选择教学周'));
    await tester.pumpAndSettle();
    backend.failOptions = null;
    await tester.tap(find.text('重新获取'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('合成教学第3周'), findsOneWidget);
    expect(backend.scheduleReads, hasLength(1));
  });
  testWidgets('旧周名称在手机顶栏只占一行，长名称不挤压工具图标', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = ScheduleNavigationBackend(state: 'long');
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
        initialTab: 1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Card, FeatureId.schedule.title));
    await tester.pumpAndSettle();
    final heading = tester.widget<Text>(find.text(backend.title('合成教学第4周')));
    expect(heading.maxLines, 1);
    expect(heading.overflow, TextOverflow.ellipsis);
  });
  testWidgets('课表刷新失败保留旧课程的教学周日期与名称', (tester) async {
    final backend = ScheduleNavigationBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
        initialTab: 1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Card, FeatureId.schedule.title));
    await tester.pumpAndSettle();
    backend.fail = true;
    await tester.tap(find.byTooltip('刷新当前查询'));
    await tester.pumpAndSettle();
    expect(find.text('以下为上次成功加载的数据。'), findsWidgets);
    expect(find.text('9-7'), findsOneWidget);
    expect(find.text('合成教学第4周'), findsOneWidget);
  });
  testWidgets('周次未返回时退出不在后台继续读课表，回来后才能推进', (tester) async {
    final gate = Completer<void>();
    final backend = ScheduleNavigationBackend()..weekGate = gate;
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
        initialTab: 1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Card, FeatureId.schedule.title));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      backend.selections.any((q) => q.view == FeatureQueryView.scheduleWeeks),
      isTrue,
    );
    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(backend.scheduleReads, isEmpty);
    await tester.tap(find.widgetWithText(Card, FeatureId.schedule.title));
    await tester.pumpAndSettle();
    expect(backend.scheduleReads, hasLength(1));
    expect(find.text('9-7'), findsOneWidget);
  });
  testWidgets('周选择只改草稿，关闭重开保留，明确应用后更新日期', (tester) async {
    final backend = ScheduleNavigationBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
        initialTab: 1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Card, FeatureId.schedule.title));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索与筛选'));
    await tester.pumpAndSettle();
    expect(find.text('选择教学周'), findsOneWidget);
    await tester.tap(find.text('选择教学周'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('合成教学第5周'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '完成'));
    await tester.pumpAndSettle();
    expect(backend.scheduleReads, hasLength(1));
    expect(find.text('合成教学第4周'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索与筛选'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '周次'))
          .controller!
          .text,
      '5',
    );
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '完成'));
    await tester.pumpAndSettle();
    expect(backend.scheduleReads.last.week, 5);
    expect(find.text('合成教学第5周'), findsOneWidget);
    expect(find.text('9-14'), findsOneWidget);
  });
  testWidgets('换学期清除旧周次，按真实周列表顺序切换草稿', (tester) async {
    final backend = ScheduleNavigationBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
        initialTab: 1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Card, FeatureId.schedule.title));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索与筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择学期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('合成上一学期'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '周次'))
          .controller!
          .text,
      isEmpty,
    );
    await tester.tap(find.text('选择教学周'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('合成教学第4周'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上一教学周'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '周次'))
          .controller!
          .text,
      '3',
    );
    expect(backend.scheduleReads, hasLength(1));
    expect(backend.selections.last.term, '2025-2026-2');
  });
  testWidgets('课表按旧顺序自动显示唯一当前周，七日标题使用真实日期', (tester) async {
    final backend = ScheduleNavigationBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
        initialTab: 1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Card, FeatureId.schedule.title));
    await tester.pumpAndSettle();
    expect(find.text('合成教学第4周'), findsOneWidget);
    expect(find.text('9-7'), findsOneWidget);
    expect(find.text('9-13'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(backend.scheduleReads.single.term, '2026-2027-1');
    expect(backend.scheduleReads.single.week, 4);
    expect(tester.takeException(), isNull);
  });
  testWidgets('无唯一当前学期不擅自查询第一学期的周课表', (tester) async {
    final backend = ScheduleNavigationBackend(state: 'no-current');
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
        initialTab: 1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Card, FeatureId.schedule.title));
    await tester.pumpAndSettle();
    expect(find.text('请从右上角选择学期和教学周'), findsOneWidget);
    expect(backend.scheduleReads, isEmpty);
    expect(
      backend.selections.where((q) => q.view == FeatureQueryView.scheduleWeeks),
      isEmpty,
    );
  });
}

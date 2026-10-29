import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart' show UiDestination;
import '../../support/schedule/navigation/backend.dart';

Future<void> mount(
  WidgetTester tester,
  ScheduleNavigationBackend backend,
) async {
  await tester.pumpWidget(
    UbaaFlutterApp(
      backend: backend,
      credentialVault: MemoryCredentialVault(),
      initialDestination: UiDestination.academic,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(Card, FeatureId.schedule.title));
  if (backend.weekGate != null) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  } else {
    await tester.pumpAndSettle();
  }
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('课表横向表格内部下拉沿当前学期周次刷新', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = ScheduleNavigationBackend();
    await mount(tester, backend);
    final selected = backend.scheduleReads.last;
    final before = backend.scheduleReads.length;
    await tester.dragFrom(const Offset(190, 300), const Offset(0, 330));
    await tester.pumpAndSettle();
    expect(backend.scheduleReads.length, before + 1);
    expect(backend.scheduleReads.last.hasSameParameters(selected), isTrue);
  });

  testWidgets('顶栏直接选择学期，取消不查询，确认后读取新学期当前周', (tester) async {
    final backend = ScheduleNavigationBackend();
    await mount(tester, backend);
    await tap(tester, find.byTooltip('选择学期'));
    await tap(tester, find.widgetWithText(TextButton, '取消'));
    expect(backend.scheduleReads.length, 1);
    await tap(tester, find.byTooltip('选择学期'));
    await tap(tester, find.text('合成上一学期'));
    expect(backend.scheduleReads.last.term, '2025-2026-2');
    expect(backend.scheduleReads.last.week, 4);
    expect(find.text('3-10'), findsOneWidget);
  });

  testWidgets('大字长周名称不被本周标记挤成窄列', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final backend = ScheduleNavigationBackend(state: 'long');
    await mount(tester, backend);
    await tap(tester, find.text(backend.title('合成教学第4周')));
    Finder option(int n) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(backend.title('合成教学第$n周')),
    );
    expect(
      tester.getSize(option(4)).width,
      greaterThanOrEqualTo(tester.getSize(option(3)).width - 48),
    );
  });

  testWidgets('周选项失败后重新获取恢复列表且不发课程查询', (tester) async {
    final backend = ScheduleNavigationBackend();
    await mount(tester, backend);
    backend.failOptions = FeatureQueryView.scheduleWeeks;
    await tap(tester, find.text('合成教学第4周'));
    backend.failOptions = null;
    await tap(tester, find.text('重新获取'));
    expect(find.text('合成教学第3周'), findsOneWidget);
    expect(backend.scheduleReads, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('周次条长名称单行省略，顶栏工具仍可点击', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = ScheduleNavigationBackend(state: 'long');
    await mount(tester, backend);
    final heading = tester.widget<Text>(find.text(backend.title('合成教学第4周')));
    expect(heading.maxLines, 1);
    expect(heading.overflow, TextOverflow.ellipsis);
    await tap(tester, find.byTooltip('选择学期'));
    await tap(tester, find.text('合成上一学期'));
    expect(backend.scheduleReads.last.term, '2025-2026-2');
  });

  testWidgets(
    '课表刷新失败保留旧课程的教学周日期与名称',
    (tester) async {
      final backend = ScheduleNavigationBackend();
      await mount(tester, backend);
      backend.fail = true;
      await tap(tester, find.byTooltip('刷新当前查询'));
      expect(find.text('9-7'), findsOneWidget);
      expect(find.text('合成教学第4周'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('周次未返回时退出不在后台继续读课表，回来后才能推进', (tester) async {
    final gate = Completer<void>();
    final backend = ScheduleNavigationBackend()..weekGate = gate;
    await mount(tester, backend);
    expect(
      backend.selections.any((q) => q.view == FeatureQueryView.scheduleWeeks),
      isTrue,
    );
    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(backend.scheduleReads, isEmpty);
    await tap(tester, find.widgetWithText(Card, FeatureId.schedule.title));
    expect(backend.scheduleReads, hasLength(1));
    expect(find.text('9-7'), findsOneWidget);
  });

  testWidgets('周次选择取消保留当前周，选择后立即更新课程与日期', (tester) async {
    final backend = ScheduleNavigationBackend();
    await mount(tester, backend);
    await tap(tester, find.text('合成教学第4周'));
    await tap(tester, find.widgetWithText(TextButton, '取消'));
    expect(backend.scheduleReads, hasLength(1));
    await tap(tester, find.text('合成教学第4周'));
    await tap(tester, find.text('合成教学第5周'));
    expect(backend.scheduleReads.last.week, 5);
    expect(find.text('9-14'), findsOneWidget);
  });

  testWidgets('换学期后按该学期真实周列表切换', (tester) async {
    final backend = ScheduleNavigationBackend();
    await mount(tester, backend);
    await tap(tester, find.byTooltip('选择学期'));
    await tap(tester, find.text('合成上一学期'));
    await tap(tester, find.byTooltip('上一周'));
    expect(backend.scheduleReads.last.term, '2025-2026-2');
    expect(backend.scheduleReads.last.week, 3);
    expect(find.text('3-3'), findsOneWidget);
  });

  testWidgets('课表自动进入唯一当前周并使用真实七日日期', (tester) async {
    final backend = ScheduleNavigationBackend();
    await mount(tester, backend);
    expect(find.text('合成教学第4周'), findsOneWidget);
    expect(find.text('9-7'), findsOneWidget);
    expect(find.text('9-13'), findsOneWidget);
    expect(backend.scheduleReads.single.term, '2026-2027-1');
    expect(backend.scheduleReads.single.week, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无唯一当前学期不猜默认，明确选择后可进入课表', (tester) async {
    final backend = ScheduleNavigationBackend(state: 'no-current');
    await mount(tester, backend);
    expect(backend.scheduleReads, isEmpty);
    expect(
      backend.selections.where((q) => q.view == FeatureQueryView.scheduleWeeks),
      isEmpty,
    );
    expect(find.text('合成本学期'), findsNothing);
    await tap(tester, find.byTooltip('选择学期'));
    await tap(tester, find.text('合成本学期'));
    expect(find.text('合成教学第4周'), findsNothing);
    await tap(tester, find.text('选择周次'));
    await tap(tester, find.text('合成教学第4周'));
    expect(backend.scheduleReads.single.term, '2026-2027-1');
    expect(backend.scheduleReads.single.week, 4);
  });
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'flow_test.dart' show app, opened;
import 'actions_test.dart' show saveEditor;
import 'view_modes_test.dart' show course, reveal;
import 'support.dart';

void viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('搜索中的词语导航不切换日期，导航按钮聚焦后支持键盘切周', (tester) async {
    final backend = MemoryAgenda();
    final actual = await opened(backend);
    await tester.pumpWidget(app(actual));
    await tester.pumpAndSettle();
    final search = find.widgetWithText(TextField, '搜索日程');
    await reveal(tester, search);
    await tester.enterText(search, '课程 安排');
    final original = backend.lastQuery!.to;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(backend.lastQuery!.to, original, reason: '编辑搜索文字时保留平台的词语导航');
    FocusManager.instance.primaryFocus?.unfocus();
    await reveal(tester, find.text('今天'), fromTop: true);
    Focus.of(tester.element(find.text('今天'))).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(backend.lastQuery!.to, isNot(original));
  });

  testWidgets('手机周视图初始显示焦点日期，刷新不夺回手动滚动位置', (tester) async {
    viewport(tester, const Size(360, 850));
    final backend = MemoryAgenda()..school.add(course());
    final service = await opened(backend);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();
    final grid = find.byKey(const ValueKey('agenda-week-grid'));
    await tester.drag(
      find.byKey(const ValueKey('agenda-main-scroll')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('合成课程时段').hitTestable(),
      findsOneWidget,
      reason: '打开周视图时当前焦点日期必须在手机可见范围内',
    );
    await tester.drag(grid, const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('合成课程时段').hitTestable(), findsNothing);
    final horizontal = find
        .ancestor(
          of: grid,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.right,
          ),
        )
        .first;
    final scrolledDate = tester
        .state<ScrollableState>(horizontal)
        .position
        .pixels;
    final vertical = find
        .descendant(of: grid, matching: find.byType(Scrollable))
        .first;
    final previousTime = tester
        .state<ScrollableState>(vertical)
        .position
        .pixels;
    await tester.dragFrom(
      tester
          .getRect(grid)
          .intersect(
            tester.getRect(find.byKey(const ValueKey('agenda-main-scroll'))),
          )
          .center,
      const Offset(0, -140),
    );
    await tester.pumpAndSettle();
    final scrolledTime = tester
        .state<ScrollableState>(vertical)
        .position
        .pixels;
    expect(scrolledTime, greaterThan(previousTime));
    final snapshot = await backend.query(backend.lastQuery!);
    backend.gate = Completer<AgendaQueryResult>();
    await reveal(tester, find.text('刷新本机数据'), fromTop: true);
    await tester.tap(find.text('刷新本机数据'));
    await tester.pump();
    backend.gate!.complete(snapshot);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('agenda-main-scroll')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(find.text('合成课程时段').hitTestable(), findsNothing);
    expect(
      tester.state<ScrollableState>(horizontal).position.pixels,
      closeTo(scrolledDate, .01),
      reason: '查询等待前后的日期滚动位置保持不变',
    );
    expect(
      tester.state<ScrollableState>(vertical).position.pixels,
      closeTo(scrolledTime, .01),
      reason: '查询等待前后的时间滚动位置保持不变',
    );
  });

  testWidgets('宽屏详情栏编辑备注，刷新保留选择，路线变化清除旧详情', (tester) async {
    viewport(tester, const Size(1600, 1000));
    final backend = MemoryAgenda()..school.add(course());
    final service = await opened(backend);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('合成课程时段'));
    await tester.pumpAndSettle();
    final pane = find.byKey(const ValueKey('agenda-detail-pane'));
    expect(
      find.descendant(of: pane, matching: find.text('学校状态：已缓存')),
      findsOneWidget,
    );
    await tester.tap(find.text('刷新本机数据'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: pane, matching: find.text('学校状态：已缓存')),
      findsOneWidget,
    );
    await tester.enterText(find.widgetWithText(TextField, '本地备注'), '宽屏备注');
    await tester.tap(find.text('保存备注'));
    await tester.pumpAndSettle();
    expect(backend.overlays.values.single.value.note, '宽屏备注');
    await tester.tap(find.text('合成课程时段'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-day-2026-11-06')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: pane, matching: find.text('选择事项查看详情')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('agenda-day-2026-11-05')));
    await tester.pumpAndSettle();
    backend.gate = Completer();
    await tester.pumpWidget(app(service, scope: 2));
    await tester.pump();
    expect(find.widgetWithText(TextField, '本地备注'), findsNothing);
    expect(
      find.descendant(of: pane, matching: find.text('选择事项查看详情')),
      findsOneWidget,
    );
    backend.gate!.complete(AgendaQueryResult(entries: [], sources: []));
    await tester.pumpAndSettle();
  });

  testWidgets('360像素大字体与键盘下可切换视图，搜索值保持且日期标记对应事项', (tester) async {
    viewport(tester, const Size(360, 850));
    final backend = MemoryAgenda()..school.add(course());
    final service = await opened(backend);
    await tester.pumpWidget(
      app(service, textScaler: const TextScaler.linear(1.8)),
    );
    await tester.pumpAndSettle();
    final search = find.widgetWithText(TextField, '搜索日程');
    await reveal(tester, search);
    expect(MediaQuery.textScalerOf(tester.element(search)).scale(10), 18);
    await tester.enterText(search, '合成课程');
    FocusManager.instance.primaryFocus?.unfocus();
    await reveal(tester, find.text('月'), fromTop: true);
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    final day = find.byKey(const ValueKey('agenda-day-2026-11-05'));
    await reveal(tester, day);
    expect(tester.getSemantics(day).label, contains('2026-11-05，1项'));
    await tester.tap(day);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('周'), fromTop: true);
    await tester.tap(find.text('周'));
    await tester.pumpAndSettle();
    await reveal(tester, search, fromTop: true);
    expect(tester.widget<TextField>(search).controller!.text, '合成课程');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('agenda-main-scroll'))).height,
      570,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('路线变化同时撤销冲突提示和旧编辑器，不能继续保存', (tester) async {
    final backend = MemoryAgenda()..school.add(course());
    final service = await opened(backend);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建事项'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('agenda-title')), '旧路线安排');
    await tester.enterText(
      find.byKey(const ValueKey('agenda-start')),
      '2026-11-05 10:00',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agenda-end')),
      '2026-11-05 11:00',
    );
    await saveEditor(tester);
    expect(find.text('与已缓存课程重叠'), findsOneWidget);
    await tester.pumpWidget(app(service, scope: 2));
    await tester.pumpAndSettle();
    expect(find.text('仍然保存'), findsNothing);
    expect(find.text('保存事项'), findsNothing);
    expect(backend.writes, 0);
  });
}

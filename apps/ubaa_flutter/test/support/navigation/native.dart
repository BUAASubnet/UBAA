import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 定位用户当前可操作的导航入口，兼容底栏、紧凑侧栏及展开侧栏。
Finder uiDestinationFinder(WidgetTester tester, UiDestination destination) {
  if (find.byType(NavigationBar).evaluate().isNotEmpty) {
    return find.byType(NavigationDestination).at(destination.index);
  }
  final rail = find.byType(NavigationRail);
  if (rail.evaluate().isNotEmpty) {
    // 设置位于侧栏底部按钮，选中状态与分组目的地分别维护，按实际图标定位。
    final selected = find.descendant(
      of: rail,
      matching: find.byIcon(destination.selectedIcon),
    );
    return selected.evaluate().isNotEmpty
        ? selected.first
        : find
              .descendant(of: rail, matching: find.byIcon(destination.icon))
              .first;
  }
  // 展开侧栏在页面正文之前构建；正文可能含同名条目，取侧栏中的第一项。
  return find.widgetWithText(ListTile, destination.label).first;
}

/// 窄屏从抽屉打开工具页，桌面“关于”从侧栏底部的可见入口打开。
Future<void> uiOpenUtility(WidgetTester tester, String title) async {
  final menu = find.byIcon(Icons.menu);
  if (menu.hitTestable().evaluate().isNotEmpty) {
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, title));
    await tester.pumpAndSettle();
    return;
  }
  if (title == '关于') {
    final button = find.byTooltip(title).hitTestable();
    final entry = button.evaluate().isNotEmpty
        ? button
        : find.widgetWithText(ListTile, title).hitTestable();
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    return;
  }
  await tester.tap(uiDestinationFinder(tester, UiDestination.settings));
  await tester.pumpAndSettle();
  if (title == UiDestination.settings.label) return;
  final entry = find.widgetWithText(Card, title);
  if (entry.evaluate().isEmpty) {
    // 设置正文按需构建；末个纵向滚动器属于正文，前面的滚动器属于侧栏。
    final bodyScroll = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .last;
    await tester.scrollUntilVisible(entry, 220, scrollable: bodyScroll);
  }
  expect(entry, findsOneWidget);
  await tester.ensureVisible(entry);
  await tester.pumpAndSettle();
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

Future<void> uiOpenProfile(WidgetTester tester) =>
    uiOpenUtility(tester, '我的资料');

/// 等待业务状态或目标控件出现，不要求后台动画停止。
Future<void> uiWaitFor(
  WidgetTester tester,
  bool Function() ready,
  String reason, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final timer = Stopwatch()..start();
  while (!ready() && timer.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue, reason: reason);
}

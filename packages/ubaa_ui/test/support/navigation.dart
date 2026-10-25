import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 回归用例沿实际分类入口进入领域，查询和写入断言继续由原用例负责。
Future<void> openFeature(WidgetTester tester, FeatureId feature) async {
  final destination = UiDestination.forFeature(feature);
  final nav = find.byType(NavigationBar);
  if (nav.evaluate().isNotEmpty) {
    await tester.tap(find.byType(NavigationDestination).at(destination.index));
  } else {
    final selected = find.byIcon(destination.selectedIcon);
    final target = selected.evaluate().isNotEmpty
        ? selected
        : find.byIcon(destination.icon);
    await tester.ensureVisible(target.first);
    await tester.tap(target.first);
  }
  await tester.pumpAndSettle();
  final card = find.widgetWithText(Card, feature.title);
  if (card.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      card,
      200,
      scrollable: find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    );
  }
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
  final landing = find.byKey(ValueKey(('feature-landing', feature)));
  if (landing.evaluate().isNotEmpty) {
    final title = switch (feature) {
      FeatureId.bykc => '选择课程',
      FeatureId.libbook => '预约座位',
      FeatureId.cgyy => '预约研讨室',
      _ => throw StateError('意外子菜单'),
    };
    await tester.tap(
      find.descendant(of: landing, matching: find.widgetWithText(Card, title)),
    );
    await tester.pumpAndSettle();
  }
}

/// 只沿用户可操作入口打开面板；入口缺失必须使调用测试失败。
Future<void> openQueryPanel(WidgetTester tester) async {
  if (find
      .widgetWithText(TextButton, '完成')
      .hitTestable()
      .evaluate()
      .isNotEmpty) {
    return;
  }
  final candidates = <Finder>[
    find.byTooltip('搜索与筛选'),
    find.byTooltip('排序与筛选'),
    find.widgetWithText(FilledButton, '筛选'),
    find.widgetWithText(FilledButton, '调整'),
  ];
  for (final candidate in candidates) {
    final visible = candidate.hitTestable();
    if (visible.evaluate().isEmpty) continue;
    expect(visible, findsOneWidget, reason: '筛选入口必须唯一且可点击');
    await tester.tap(visible);
    await tester.pumpAndSettle();
    return;
  }
  fail('找不到可点击的筛选入口；测试不得直接修改页面内部状态');
}

Future<void> closeQueryPanel(WidgetTester tester) async {
  if (find.widgetWithText(TextButton, '完成').evaluate().isNotEmpty) {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '完成'));
    await tester.pumpAndSettle();
  }
}

Future<void> openUtility(WidgetTester tester, String title) async {
  final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
  if (scaffold.drawer != null) {
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Drawer), matching: find.text(title)),
    );
  } else if (title == '我的资料') {
    await tester.tap(find.byType(Image).first);
  } else {
    final target = find.byTooltip(title).evaluate().isNotEmpty
        ? find.byTooltip(title)
        : find.text(title).first;
    await tester.ensureVisible(target);
    await tester.tap(target);
  }
  await tester.pumpAndSettle();
}

Future<String> queryFieldText(WidgetTester tester, String label) async {
  await openQueryPanel(tester);
  final text = tester
      .widget<TextField>(find.widgetWithText(TextField, label))
      .controller!
      .text;
  await closeQueryPanel(tester);
  return text;
}

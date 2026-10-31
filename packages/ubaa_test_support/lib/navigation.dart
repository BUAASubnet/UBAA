import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 回归用例沿实际分类入口进入领域，查询和写入断言继续由原用例负责。
/// 确保目标可见后点击，并等待一次稳定帧。
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

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
/// 列表顶部常驻的搜索框；搜索不再藏在面板中。
final searchField = find.byKey(const ValueKey<String>('feature-search-field'));

/// 打开当前列表的筛选面板；没有可调条件的页面只有常驻搜索框，调用即失败。
Future<void> openQueryPanel(WidgetTester tester) async {
  if (find.byTooltip('关闭筛选').hitTestable().evaluate().isNotEmpty) return;
  final button = find.byKey(const ValueKey<String>('feature-filter-button'));
  if (button.hitTestable().evaluate().isEmpty) {
    fail('找不到可点击的筛选入口；测试不得直接修改页面内部状态');
  }
  expect(button.hitTestable(), findsOneWidget, reason: '筛选入口必须唯一且可点击');
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> closeQueryPanel(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final close = find.byTooltip('关闭筛选').hitTestable();
  if (close.evaluate().isNotEmpty) {
    await tester.tap(close);
    await tester.pumpAndSettle();
  }
}

Future<void> openUtility(WidgetTester tester, String title) async {
  final mobile = find.byType(NavigationBar).evaluate().isNotEmpty;
  if (mobile || title == '我的资料' || title == '我的') {
    final target = mobile
        ? find.byKey(const ValueKey('tab-我的'))
        : find.byType(Image).first;
    await tester.tap(target);
    await tester.pumpAndSettle();
    if (title == '我的') return;
  }
  final target = title == '我的资料'
      ? find.byKey(const ValueKey('me-profile'))
      : find.byTooltip(title).evaluate().isNotEmpty
      ? find.byTooltip(title)
      : find.text(title).last;
  await tester.scrollUntilVisible(
    target,
    250,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// 读取常驻搜索框中的关键字。
String searchText(WidgetTester tester) =>
    tester.widget<TextField>(searchField).controller!.text;

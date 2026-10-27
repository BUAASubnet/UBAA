part of '../flow_test.dart';

/// 沿实际分类入口、懒加载卡片与子菜单点击；不绕过生产导航状态。
Future<void> _returnToFeatureRoot(WidgetTester tester) async {
  await _closeIntegrationPanel(tester);
  for (
    var attempt = 0;
    attempt < 5 && find.byTooltip('返回').evaluate().isNotEmpty;
    attempt++
  ) {
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
  }
  expect(find.byType(UbaaMainShell), findsOneWidget);
}

Future<void> _openIntegrationFeature(
  WidgetTester tester,
  FeatureId feature, {
  bool enterLanding = true,
}) async {
  await _returnToFeatureRoot(tester);
  final index = UiDestination.forFeature(feature).index;
  if (find.byType(NavigationBar).evaluate().isNotEmpty) {
    await tester.tap(find.byType(NavigationDestination).at(index));
  } else {
    final destination = UiDestination.forFeature(feature);
    final selected = find.byIcon(destination.selectedIcon);
    final target = selected.evaluate().isNotEmpty
        ? selected
        : find.byIcon(destination.icon);
    await tester.ensureVisible(target.first);
    await tester.tap(target.first);
  }
  await tester.pumpAndSettle();
  final target = await _scrollToQueryFeature(tester, feature);
  await tester.tap(target);
  await tester.pumpAndSettle();
  expect(find.byTooltip('返回'), findsOneWidget);
  final landing = find.byKey(ValueKey(('feature-landing', feature)));
  if (enterLanding && landing.evaluate().isNotEmpty) {
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

/// 打开当前列表的筛选面板；搜索框常驻列表上方，不经面板。
Future<void> _openIntegrationPanel(WidgetTester tester) async {
  if (find.byTooltip('关闭筛选').hitTestable().evaluate().isNotEmpty) return;
  final button = find.byKey(const ValueKey<String>('feature-filter-button'));
  expect(button.hitTestable(), findsOneWidget, reason: '当前页面必须提供筛选入口');
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _closeIntegrationPanel(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final close = find.byTooltip('关闭筛选').hitTestable();
  if (close.evaluate().isNotEmpty) {
    await tester.tap(close);
    await tester.pumpAndSettle();
  }
}

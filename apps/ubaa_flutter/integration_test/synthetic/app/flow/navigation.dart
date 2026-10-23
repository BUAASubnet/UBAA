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

Future<void> _openIntegrationPanel(WidgetTester tester) async {
  if (find.widgetWithText(TextButton, '完成').evaluate().isNotEmpty) return;
  await tester.tap(find.byTooltip('搜索与筛选'));
  await tester.pumpAndSettle();
}

Future<void> _closeIntegrationPanel(WidgetTester tester) async {
  final close = find.widgetWithText(TextButton, '完成');
  if (close.evaluate().isNotEmpty) {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(close);
    await tester.pumpAndSettle();
  }
}

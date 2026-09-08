import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 回归用例沿实际三入口进入领域，查询和写入断言继续由原用例负责。
Future<void> openFeature(WidgetTester tester, FeatureId feature) async {
  final index = ordinaryFeatureIds.contains(feature) ? 1 : 2;
  final nav = find.byType(NavigationBar);
  if (nav.evaluate().isNotEmpty) {
    await tester.tap(find.byType(NavigationDestination).at(index));
  } else if (find.byType(NavigationRail).evaluate().isNotEmpty) {
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    if (rail.selectedIndex != index) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byIcon(
            index == 1 ? Icons.apps_outlined : Icons.auto_awesome_outlined,
          ),
        ),
      );
    }
  } else {
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NavigationDestination).at(index));
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
}

Future<void> openQueryPanel(WidgetTester tester) async {
  if (find.widgetWithText(TextButton, '完成').evaluate().isEmpty) {
    await tester.tap(find.byTooltip('搜索与筛选'));
    await tester.pumpAndSettle();
  }
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
  tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(Drawer), matching: find.text(title)),
  );
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

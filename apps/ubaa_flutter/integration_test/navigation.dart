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
    final selected =
        tester.widget<NavigationRail>(rail).selectedIndex == destination.index;
    return find.descendant(
      of: rail,
      matching: find.byIcon(
        selected ? destination.selectedIcon : destination.icon,
      ),
    );
  }
  return find.widgetWithText(ListTile, destination.label);
}

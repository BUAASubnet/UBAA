import 'package:flutter/material.dart';

import '../../shared/tab_navigation.dart' show CompactNavigationBar;
import '../destination.dart';

/// 窄屏底部导航：放四个分类和“我的”；设置、关于与退出收在“我的”页。
Widget uiShellBottomBar(
  BuildContext context, {
  required int selectedIndex,
  required ValueChanged<int> onSelectTab,
}) => CompactNavigationBar(
  child: NavigationBar(
    height: 56 + (MediaQuery.textScalerOf(context).scale(12) - 12) * 3,
    selectedIndex: selectedIndex < UiDestination.settings.index
        ? selectedIndex
        : 0,
    onDestinationSelected: onSelectTab,
    destinations: UiDestination.values
        .take(UiDestination.settings.index)
        .map(
          (tab) => NavigationDestination(
            key: ValueKey<String>('tab-${tab.label}'),
            icon: Icon(tab.icon),
            selectedIcon: Icon(tab.selectedIcon),
            label: tab.label,
          ),
        )
        .toList(),
  ),
);

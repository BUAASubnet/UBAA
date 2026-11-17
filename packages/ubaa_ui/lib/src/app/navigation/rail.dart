import 'package:flutter/material.dart';

import '../../features/home/shell_helpers.dart' show homeRailButtonStyle;
import '../destination.dart';

/// 宽屏侧边导航：窄于 1000 时为图标栏，更宽时为带文字的抽屉式列表。
Widget uiShellRail(
  BuildContext context, {
  required int selectedIndex,
  required String? utilityPage,
  required bool featureOpen,
  required Widget Function(bool extended) leading,
  required ValueChanged<int> onSelectTab,
  required VoidCallback onOpenAbout,
}) {
  final extended = MediaQuery.sizeOf(context).width >= 1000;
  final colors = Theme.of(context).colorScheme;
  if (!extended) {
    final railButtonStyle = homeRailButtonStyle(colors);
    // 矮窗口收紧间距、设置紧跟分组、省去“关于”（在“我的”页），不再遮住分组。
    return LayoutBuilder(
      builder: (context, constraints) {
        final short = constraints.maxHeight < 560;
        return NavigationRail(
          scrollable: true,
          minWidth: 88,
          selectedIndex: selectedIndex < 4 && utilityPage == null
              ? selectedIndex
              : null,
          onDestinationSelected: onSelectTab,
          labelType: NavigationRailLabelType.none,
          leading: leading(false),
          trailingAtBottom: !short,
          trailing: Padding(
            padding: EdgeInsets.only(bottom: short ? 8 : 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '设置',
                  isSelected:
                      selectedIndex == UiDestination.settings.index &&
                      utilityPage == null,
                  style: railButtonStyle,
                  onPressed: () => onSelectTab(UiDestination.settings.index),
                  icon: Icon(UiDestination.settings.icon),
                  selectedIcon: Icon(UiDestination.settings.selectedIcon),
                ),
                if (!short) ...[
                  const SizedBox(height: 8),
                  IconButton(
                    tooltip: '关于',
                    isSelected: utilityPage == '关于' && !featureOpen,
                    style: railButtonStyle,
                    onPressed: onOpenAbout,
                    icon: const Icon(Icons.info_outline),
                  ),
                ],
              ],
            ),
          ),
          destinations: UiDestination.values
              .take(4)
              .map(
                (tab) => NavigationRailDestination(
                  padding: EdgeInsets.symmetric(vertical: short ? 0 : 8),
                  icon: Tooltip(
                    message: tab.label,
                    excludeFromSemantics: true,
                    child: Icon(tab.icon),
                  ),
                  selectedIcon: Tooltip(
                    message: tab.label,
                    excludeFromSemantics: true,
                    child: Icon(tab.selectedIcon),
                  ),
                  label: Text(tab.label),
                ),
              )
              .toList(),
        );
      },
    );
  }
  Widget entry(UiDestination tab) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    child: ListTile(
      selected: selectedIndex == tab.index && utilityPage == null,
      selectedTileColor: colors.secondaryContainer,
      selectedColor: colors.onSecondaryContainer,
      leading: Icon(selectedIndex == tab.index ? tab.selectedIcon : tab.icon),
      title: Text(tab.label),
      onTap: () => onSelectTab(tab.index),
    ),
  );
  return Material(
    color: colors.surfaceContainer,
    child: SizedBox(
      width: 248,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              child: leading(true),
            ),
            Expanded(
              child: ListView(
                primary: false,
                children: [
                  for (final tab in UiDestination.values.take(4)) entry(tab),
                ],
              ),
            ),
            entry(UiDestination.settings),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 3, 12, 16),
              child: ListTile(
                selected: utilityPage == '关于' && !featureOpen,
                selectedTileColor: colors.secondaryContainer,
                selectedColor: colors.onSecondaryContainer,
                leading: Icon(
                  utilityPage == '关于' ? Icons.info : Icons.info_outline,
                ),
                title: const Text('关于'),
                onTap: onOpenAbout,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

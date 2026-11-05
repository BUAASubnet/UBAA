import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 云盘顶部单行工具栏：文档库切换、筛选、刷新与更多菜单。
class BhpanToolbar extends StatelessWidget {
  const BhpanToolbar({
    super.key,
    required this.label,
    required this.icon,
    required this.rootNames,
    required this.current,
    required this.busy,
    required this.showSearch,
    required this.searchVisible,
    required this.showHome,
    required this.showFast,
    required this.fastEnabled,
    required this.onRoot,
    required this.onToggleSearch,
    required this.onRefresh,
    required this.onMenu,
  });
  final String label;
  final IconData icon;
  final Map<BhpanRootKind, String> rootNames;
  final BhpanRootKind? current;
  final bool busy, showSearch, searchVisible, showHome, showFast, fastEnabled;
  final ValueChanged<BhpanRootKind> onRoot;
  final VoidCallback onToggleSearch, onRefresh;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
      child: Row(
        children: [
          Flexible(
            child: PopupMenuButton<BhpanRootKind>(
              tooltip: '切换文档库',
              enabled: !busy,
              onSelected: onRoot,
              itemBuilder: (_) => [
                for (final kind in BhpanRootKind.values)
                  CheckedPopupMenuItem(
                    value: kind,
                    checked: kind == current,
                    child: Text(rootNames[kind]!),
                  ),
              ],
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: colors.onSecondaryContainer),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      color: colors.onSecondaryContainer,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          if (showSearch)
            IconButton(
              tooltip: '筛选名称',
              isSelected: searchVisible,
              onPressed: onToggleSearch,
              icon: const Icon(Icons.search),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: busy ? null : onRefresh,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: '更多云盘操作',
            enabled: !busy,
            onSelected: onMenu,
            itemBuilder: (_) => [
              if (showHome)
                const PopupMenuItem(
                  value: 'home',
                  child: ListTile(
                    leading: Icon(Icons.home_outlined),
                    title: Text('返回个人文档库'),
                  ),
                ),
              const PopupMenuItem(
                value: 'recycle',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('回收站'),
                ),
              ),
              const PopupMenuItem(
                value: 'shares',
                child: ListTile(leading: Icon(Icons.link), title: Text('分享管理')),
              ),
              const PopupMenuItem(
                value: 'received',
                child: ListTile(
                  leading: Icon(Icons.move_to_inbox_outlined),
                  title: Text('接收分享'),
                ),
              ),
              if (showFast)
                PopupMenuItem(
                  value: 'fast',
                  enabled: fastEnabled,
                  child: const ListTile(
                    leading: Icon(Icons.bolt_outlined),
                    title: Text('秒传'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

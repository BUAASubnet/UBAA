import 'package:flutter/material.dart';

class UiSelectionAction {
  const UiSelectionAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
    this.shortLabel,
    this.key,
  });

  final String label;
  final String? shortLabel;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;
  final Key? key;
}

/// 多选底栏：数量、全选切换和当前位置可用的批量操作。
class UiSelectionBar extends StatelessWidget {
  const UiSelectionBar({
    super.key,
    required this.count,
    required this.allSelected,
    required this.actions,
    required this.onClear,
    required this.onToggleAll,
  });
  final int count;
  final bool allSelected;
  final List<UiSelectionAction> actions;
  final VoidCallback? onClear, onToggleAll;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainer,
      elevation: 2,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '取消选择',
                    onPressed: onClear,
                    icon: const Icon(Icons.close),
                  ),
                  Expanded(
                    child: Text(
                      '已选 $count 项',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: onToggleAll,
                    child: Text(allSelected ? '取消全选' : '全选'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Row(
                children: [
                  for (final a in actions)
                    Expanded(child: _BarAction(action: a)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({required this.action});
  final UiSelectionAction action;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = action.onPressed == null
        ? colors.onSurface.withValues(alpha: .38)
        : action.danger
        ? colors.error
        : colors.onSurface;
    return Semantics(
      button: true,
      label: action.label,
      child: InkWell(
        key: action.key,
        borderRadius: BorderRadius.circular(12),
        onTap: action.onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, color: color),
              const SizedBox(height: 2),
              Text(
                action.shortLabel ?? action.label,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

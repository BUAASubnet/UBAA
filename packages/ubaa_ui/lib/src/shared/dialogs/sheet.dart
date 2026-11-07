import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 全应用统一的底部面板：只留拖动条，下滑或点外面关闭，高度贴合内容、最高 90%。
///
/// 详情、选择与简单设置用它；需要确认的操作用 uiConfirmIrreversible，
/// 内容较多的编辑用整页。
Future<T?> showUiSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * .9,
  ),
  builder: builder,
);

/// 面板骨架：加粗标题、标题下一行的来源与次要信息、可滚动内容、底部固定操作。
///
/// [onClose] 只在嵌入页面的详情栏里传入（没有拖动条可关）；模态面板不显示关闭按钮。
class UiSheetBody extends StatelessWidget {
  const UiSheetBody({
    super.key,
    required this.title,
    this.subtitle,
    this.accent,
    this.children = const [],
    this.actions = const [],
    this.primaryAction,
    this.onClose,
  });
  final String title;
  final String? subtitle;

  /// 标题下一行前的来源色圆点。
  final Color? accent;
  final List<Widget> children;

  /// 底部一排次要操作，等宽排列；建议不超过两个。
  final List<Widget> actions;

  /// 主要操作（实心按钮）单独一行占满宽度，放在次要操作上方。
  final Widget? primaryAction;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // 键盘弹出时让出键盘高度，否则避开 Home 指示条。
    final keyboard = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.paddingOf(context).bottom - 8,
    );
    final header = Padding(
      padding: EdgeInsets.fromLTRB(24, onClose == null ? 0 : 12, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (accent != null) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          subtitle!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: '关闭详情',
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
        if (actions.isNotEmpty || primaryAction != null)
          Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + keyboard),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?primaryAction,
                if (primaryAction != null && actions.isNotEmpty)
                  const SizedBox(height: 10),
                if (actions.isNotEmpty)
                  Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(child: actions[i]),
                      ],
                    ],
                  ),
              ],
            ),
          )
        else
          SizedBox(height: 16 + keyboard),
      ],
    );
  }
}

/// 面板里的一行信息：图标开头，主文字之后可带一行次要说明。
class UiInfoRow extends StatelessWidget {
  const UiInfoRow({
    super.key,
    required this.icon,
    required this.text,
    this.detail,
    this.color,
  });
  final IconData icon;
  final String text;
  final String? detail;

  /// 需要提醒时（如冲突）整行使用的颜色。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color ?? colors.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: theme.textTheme.bodyLarge?.copyWith(color: color),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 像输入框一样的占位入口，点开后再显示真正的输入框（如“添加备注…”）。
class UiSheetPlaceholderField extends StatelessWidget {
  const UiSheetPlaceholderField({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colors.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

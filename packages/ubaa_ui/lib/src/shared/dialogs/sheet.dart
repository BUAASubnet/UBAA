import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 全应用统一的面板：窄窗口是底部面板（只留拖动条，下滑或点外面关闭，高度贴合
/// 内容、最高 90%）；宽窗口改为居中对话框，标题行带关闭按钮，操作按钮靠右。
///
/// 详情、选择与简单设置用它；需要确认的操作用 uiConfirmIrreversible，
/// 内容较多的编辑用整页。
///
/// 内容本身需要纵向拖动（如可缩放的地图）时传 [enableDrag] 为 false，
/// 只能点外面或返回关闭。[dialogWidth] 是宽窗口对话框的最大宽度。
Future<T?> showUiSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool enableDrag = true,
  double dialogWidth = 480,
}) {
  final size = MediaQuery.sizeOf(context);
  if (uiPrefersDialog(context)) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogWidth,
            maxHeight: size.height * .85,
          ),
          child: _UiSheetDialogScope(child: Builder(builder: builder)),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    enableDrag: enableDrag,
    constraints: BoxConstraints(maxHeight: size.height * .9),
    builder: builder,
  );
}

/// 宽而高的窗口用居中对话框代替底部面板，避免面板横跨整个桌面窗口。
bool uiPrefersDialog(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width >= 720 && size.height >= 480;
}

/// 当前面板内容是否以对话框形式显示（右上角已有关闭按钮）。
bool uiInSheetDialog(BuildContext context) => _UiSheetDialogScope.of(context);

/// 标记面板内容正以对话框形式显示。
class _UiSheetDialogScope extends InheritedWidget {
  const _UiSheetDialogScope({required super.child});
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_UiSheetDialogScope>() != null;
  @override
  bool updateShouldNotify(_UiSheetDialogScope oldWidget) => false;
}

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
    final dialog = _UiSheetDialogScope.of(context);
    // 键盘弹出时让出键盘高度，否则避开 Home 指示条；对话框由 Dialog 自己避让。
    final keyboard = dialog
        ? 4.0
        : math.max(
            MediaQuery.viewInsetsOf(context).bottom,
            MediaQuery.paddingOf(context).bottom - 8,
          );
    final close =
        onClose ?? (dialog ? () => Navigator.maybePop(context) : null);
    final header = Padding(
      padding: EdgeInsets.fromLTRB(24, close == null ? 0 : 16, 12, 0),
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
          if (close != null)
            IconButton(
              tooltip: onClose == null ? '关闭' : '关闭详情',
              onPressed: close,
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
        if (dialog && (actions.isNotEmpty || primaryAction != null))
          // 对话框：操作按钮按桌面习惯靠右排成一行，主要操作在最右。
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [...actions, ?primaryAction],
            ),
          )
        else if (actions.isNotEmpty || primaryAction != null)
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

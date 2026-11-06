import 'package:flutter/material.dart';

/// 全应用统一的空状态与整页提示：圆形图标、标题、说明和一个可选操作。
///
/// 整页使用默认尺寸；列表或卡片内使用 [compact]，缩小图标与留白。
/// 卡片上的错误继续使用 FriendlyErrorCard，行内重试使用 [UiInlineRetry]。
class UiStatePanel extends StatelessWidget {
  const UiStatePanel({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.action,
    this.actionIcon,
    this.onAction,
    this.compact = false,
  });
  final IconData icon;
  final String title;
  final String? detail, action;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final size = compact ? 56.0 : 72.0;
    final label = action;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 24 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: size / 2, color: colors.onSurfaceVariant),
            ),
            SizedBox(height: compact ? 12 : 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            if (label != null) ...[
              SizedBox(height: compact ? 16 : 20),
              actionIcon == null
                  ? FilledButton.tonal(onPressed: onAction, child: Text(label))
                  : FilledButton.tonalIcon(
                      onPressed: onAction,
                      icon: Icon(actionIcon),
                      label: Text(label),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 行内错误：说明文字在左，「重试」文字按钮在右。
class UiInlineRetry extends StatelessWidget {
  const UiInlineRetry({
    super.key,
    required this.message,
    this.onRetry,
    this.label = '重试',
  });
  final String message;
  final VoidCallback? onRetry;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
        if (onRetry != null) TextButton(onPressed: onRetry, child: Text(label)),
      ],
    );
  }
}

import 'package:flutter/material.dart';

enum UbaaFeedbackKind { info, success, warning, error }

/// 绘制应用统一的短提示；详情动作由调用方提供。
void uiShowFeedbackNotice(
  ScaffoldMessengerState messenger,
  String message, {
  UbaaFeedbackKind kind = UbaaFeedbackKind.info,
  VoidCallback? onDetails,
}) {
  if (!messenger.mounted || message.trim().isEmpty) return;
  final context = messenger.context;
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  final attention =
      kind == UbaaFeedbackKind.warning || kind == UbaaFeedbackKind.error;
  final icon = switch (kind) {
    UbaaFeedbackKind.success => Icons.check_circle_outline,
    UbaaFeedbackKind.warning => Icons.info_outline,
    UbaaFeedbackKind.error => Icons.error_outline,
    UbaaFeedbackKind.info => Icons.info_outline,
  };
  // 新反馈替换旧消息，避免多次点击后排成长队。
  messenger
    ..clearSnackBars()
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: (MediaQuery.sizeOf(context).width - 32).clamp(1, 420).toDouble(),
        duration: Duration(seconds: attention ? 6 : 3),
        persist: attention && MediaQuery.accessibleNavigationOf(context),
        backgroundColor: colors.surfaceContainerHigh,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.outlineVariant),
        ),
        showCloseIcon: attention,
        closeIconColor: colors.onSurfaceVariant,
        action: onDetails == null
            ? null
            : SnackBarAction(label: '错误详情', onPressed: onDetails),
        content: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: kind == UbaaFeedbackKind.error
                  ? colors.error
                  : colors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}

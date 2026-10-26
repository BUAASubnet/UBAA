import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

enum UbaaFeedbackKind { info, success, warning, error }

/// 全应用的短暂操作反馈；页面错误和需要确认的操作保留在原上下文。
class UbaaFeedback {
  const UbaaFeedback._();

  static void showOutcome(BuildContext context, WriteOutcome outcome) => show(
    context,
    outcome.message,
    kind:
        outcome.result?.outcomeUnknown == true ||
            outcome.error?.code == UbaaErrorCode.outcomeUnknown
        ? UbaaFeedbackKind.warning
        : outcome.result?.success == true
        ? UbaaFeedbackKind.success
        : UbaaFeedbackKind.error,
  );

  static void show(
    BuildContext context,
    String message, {
    UbaaFeedbackKind kind = UbaaFeedbackKind.info,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) showOn(messenger, message, kind: kind);
  }

  static void showOn(
    ScaffoldMessengerState messenger,
    String message, {
    UbaaFeedbackKind kind = UbaaFeedbackKind.info,
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
          width: (MediaQuery.sizeOf(context).width - 32)
              .clamp(1, 420)
              .toDouble(),
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
}

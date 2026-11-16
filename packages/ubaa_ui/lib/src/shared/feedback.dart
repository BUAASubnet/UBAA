import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../common/error_card.dart' show uiErrorDetailsAction;

import '../common/feedback_notice.dart';

export '../common/feedback_notice.dart' show UbaaFeedbackKind;

/// 全应用的短暂操作反馈；页面错误和需要确认的操作保留在原上下文。
class UbaaFeedback {
  const UbaaFeedback._();

  static void showOutcome(BuildContext context, WriteOutcome outcome) => show(
    context,
    outcome.message,
    error: outcome.error ?? outcome.resultError,
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
    UiError? error,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      showOn(
        messenger,
        message,
        kind: kind,
        onDetails: uiErrorDetailsAction(context, error),
      );
    }
  }

  static void showWarning(
    BuildContext context,
    String message,
    Object? error,
  ) => show(
    context,
    message,
    kind: UbaaFeedbackKind.warning,
    error: error is UiError ? error : null,
  );

  static void showError(BuildContext context, String message, Object? error) =>
      show(
        context,
        message,
        kind: UbaaFeedbackKind.error,
        error: error is UiError ? error : null,
      );

  static void showOn(
    ScaffoldMessengerState messenger,
    String message, {
    UbaaFeedbackKind kind = UbaaFeedbackKind.info,
    VoidCallback? onDetails,
  }) => uiShowFeedbackNotice(
    messenger,
    message,
    kind: kind,
    onDetails: onDetails,
  );
}

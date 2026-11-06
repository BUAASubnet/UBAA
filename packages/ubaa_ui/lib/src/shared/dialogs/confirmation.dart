import 'package:flutter/material.dart';

/// 危险操作（删除、清除、退选、取消预约）的确认按钮统一使用错误色。
ButtonStyle uiDangerButtonStyle(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    backgroundColor: colors.error,
    foregroundColor: colors.onError,
  );
}

/// 不可撤销的写操作先用系统弹窗确认；其余操作点击即提交。
///
/// [danger] 为 true 时确认按钮用错误色；[dismiss] 默认「取消」，
/// 操作本身就是「取消预约」一类时传入「保留」等不会混淆的说法。
Future<bool> uiConfirmIrreversible(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool danger = false,
  String dismiss = '取消',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(dismiss),
          ),
          FilledButton(
            style: danger ? uiDangerButtonStyle(context) : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ==
    true;

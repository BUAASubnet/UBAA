import 'package:flutter/material.dart';
import '../dialogs/sheet.dart' show showUiSheet, UiSheetBody, UiInfoRow;

/// 顶栏的连接入口：需要补全登录时直接进入登录，否则查看连接状态并可重试。
class UiConnectionStatusButton extends StatelessWidget {
  const UiConnectionStatusButton({
    super.key,
    this.status,
    this.onReconnect,
    this.onCompleteLogin,
  });
  final String? status;
  final VoidCallback? onReconnect;
  final ValueChanged<BuildContext>? onCompleteLogin;

  Future<void> _open(BuildContext context) async {
    if (onCompleteLogin case final complete?) {
      complete(context);
      return;
    }
    final retry = await showUiSheet<bool>(
      context,
      builder: (context) => UiSheetBody(
        title: '连接状态',
        children: [
          UiInfoRow(icon: Icons.info_outline, text: status ?? '连接已恢复'),
        ],
        primaryAction: onReconnect == null
            ? null
            : FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('重试'),
              ),
      ),
    );
    if (retry == true && context.mounted) onReconnect?.call();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: onCompleteLogin != null ? '完成登录' : '连接状态',
    icon: Icon(
      onCompleteLogin != null
          ? Icons.person_outline
          : Icons.sync_problem_outlined,
    ),
    onPressed: () => _open(context),
  );
}

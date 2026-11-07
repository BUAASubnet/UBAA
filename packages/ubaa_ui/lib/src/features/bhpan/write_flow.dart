import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../write_callbacks.dart';
import '../../shared/dialogs/confirmation.dart';
import '../../shared/dialogs/scope_boundary.dart';

/// 写入的确认方式。
///
/// [confirmed] 为 true 表示用户已在发起界面明确确认（例如输入名称后点「新建」，
/// 或批量操作开头的统一确认），此时只要 Core 没有给出警告就直接提交。
class BhpanWriteStyle {
  const BhpanWriteStyle({this.confirmed = false, this.note});
  final bool confirmed;

  /// 显示在确认内容最前面的补充说明，例如「云端没有相同文件，将完整上传」。
  final String? note;
}

typedef BhpanWriteRunner =
    Future<WriteOutcome?> Function(
      BhpanMutation request, [
      BhpanWriteStyle style,
    ]);

/// 各类写入的确认标题、按钮文字和是否危险。
(String, String, bool) bhpanConfirmText(BhpanMutationKind kind) =>
    switch (kind) {
      BhpanMutationKind.createFolder => ('新建文件夹', '新建', false),
      BhpanMutationKind.rename => ('重命名', '重命名', false),
      BhpanMutationKind.move => ('移动到这里？', '移动', false),
      BhpanMutationKind.copy => ('复制到这里？', '复制', false),
      BhpanMutationKind.recycle => ('移入回收站？', '移入回收站', true),
      BhpanMutationKind.restore => ('从回收站恢复？', '恢复', false),
      BhpanMutationKind.deleteForever => ('永久删除？', '永久删除', true),
      BhpanMutationKind.createShare => ('创建分享链接', '创建', false),
      BhpanMutationKind.updateShare => ('保存分享设置', '保存', false),
      BhpanMutationKind.cancelShare => ('取消分享？', '取消分享', true),
      BhpanMutationKind.uploadFast => ('秒传文件', '秒传', false),
      BhpanMutationKind.upload => ('上传文件', '上传', false),
    };

String? _consequence(BhpanMutationKind kind) => switch (kind) {
  BhpanMutationKind.deleteForever => '永久删除后无法找回。',
  BhpanMutationKind.cancelShare => '取消后，已发出的链接会立即失效。',
  BhpanMutationKind.uploadFast => '云端已有相同文件，不需要上传文件内容。',
  _ => null,
};

/// 仅编排确认展示，意图与提交状态仍由 App 的唯一 WriteCoordinator 拥有。
Future<WriteOutcome?> runBhpanWriteFlow({
  required BuildContext context,
  required BhpanMutation request,
  required BhpanService service,
  required ValueListenable<int> generation,
  required WritePreparationRunner run,
  required WriteConfirmationRunner confirm,
  required WriteCancellationRunner cancel,
  required WriteState Function() state,
  required bool Function() isCurrent,
  BhpanWriteStyle style = const BhpanWriteStyle(),
}) async {
  WriteIntent? intent;
  try {
    intent = await run(
      () => service.prepare(request),
      expectedOperation: WriteOperation.bhpan,
    );
    if (!isCurrent() || intent == null || !context.mounted) return null;
    // Core 给出警告时，即使发起界面已确认，也必须让用户看到再决定。
    if (!style.confirmed || intent.warnings.isNotEmpty) {
      final accepted =
          await showDialog<bool>(
            context: context,
            builder: (c) => UiScopeBoundary(
              generation: generation,
              child: _ConfirmDialog(
                kind: request.kind,
                intent: intent!,
                note: style.note,
              ),
            ),
          ) ==
          true;
      if (!accepted || !isCurrent()) return null;
    }
    return await confirm();
  } finally {
    final current = state();
    if (intent != null &&
        current.intent?.intentId == intent.intentId &&
        !current.isSubmitting)
      await cancel();
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.kind, required this.intent, this.note});
  final BhpanMutationKind kind;
  final WriteIntent intent;
  final String? note;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (title, action, danger) = bhpanConfirmText(kind);
    final consequence = _consequence(kind);
    return AlertDialog(
      icon: danger
          ? Icon(Icons.warning_amber_rounded, color: colors.error)
          : null,
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note != null) ...[
            Text(note!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              intent.targetSummary,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (consequence != null) ...[
            const SizedBox(height: 12),
            Text(
              consequence,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: danger ? colors.error : colors.onSurfaceVariant,
              ),
            ),
          ],
          for (final warning in intent.warnings) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: colors.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(warning, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: danger ? uiDangerButtonStyle(context) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    );
  }
}

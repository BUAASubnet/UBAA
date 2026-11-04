import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../write_callbacks.dart';
import '../../shared/dialogs/scope_boundary.dart';

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
}) async {
  WriteIntent? intent;
  try {
    intent = await run(
      () => service.prepare(request),
      expectedOperation: WriteOperation.bhpan,
    );
    if (!isCurrent() || intent == null || !context.mounted) return null;
    final accepted =
        await showDialog<bool>(
          context: context,
          builder: (c) => UiScopeBoundary(
            generation: generation,
            child: AlertDialog(
              title: const Text('确认云盘操作'),
              content: Text(
                '${intent!.targetSummary}\n路线：${intent.resolvedRoute.label}\n${intent.warnings.join('\n')}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('确认提交'),
                ),
              ],
            ),
          ),
        ) ==
        true;
    if (!accepted || !isCurrent()) return null;
    return await confirm();
  } finally {
    final current = state();
    if (intent != null &&
        current.intent?.intentId == intent.intentId &&
        !current.isSubmitting)
      await cancel();
  }
}

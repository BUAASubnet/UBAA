import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'sheets.dart';
import 'write_flow.dart';

/// 多选底栏：数量、全选切换和当前位置可用的批量操作。
class BhpanSelectionBar extends StatelessWidget {
  const BhpanSelectionBar({
    super.key,
    required this.count,
    required this.allSelected,
    required this.actions,
    required this.enabled,
    required this.onClear,
    required this.onToggleAll,
    required this.onAction,
  });
  final int count;
  final bool allSelected;
  final List<BhpanAction> actions;
  final bool Function(BhpanAction) enabled;
  final VoidCallback onClear, onToggleAll;
  final ValueChanged<BhpanAction> onAction;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainer,
      elevation: 2,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '取消选择',
                    onPressed: onClear,
                    icon: const Icon(Icons.close),
                  ),
                  Expanded(
                    child: Text(
                      '已选 $count 项',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: onToggleAll,
                    child: Text(allSelected ? '取消全选' : '全选'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Row(
                children: [
                  for (final a in actions)
                    Expanded(
                      child: _BarAction(
                        action: a,
                        enabled: enabled(a),
                        onTap: () => onAction(a),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.action,
    required this.enabled,
    required this.onTap,
  });
  final BhpanAction action;
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = !enabled
        ? colors.onSurface.withValues(alpha: .38)
        : action.danger
        ? colors.error
        : colors.onSurface;
    return Semantics(
      button: true,
      label: action.label,
      child: InkWell(
        key: ValueKey('bhpan-batch-${action.name}'),
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, color: color),
              const SizedBox(height: 2),
              Text(
                action == BhpanAction.copy ? '复制' : action.label,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum BhpanBatchStatus {
  done('已完成'),
  failed('失败'),
  unknown('结果待核对'),
  skipped('尚未执行');

  const BhpanBatchStatus(this.label);
  final String label;
}

/// 逐项执行；结果未知或用户中途取消后停止发送，其余条目标为尚未执行。
Future<List<(String, BhpanBatchStatus)>?> bhpanRunBatch(
  List<BhpanItem> items,
  Future<WriteOutcome?> Function(BhpanItem) run, {
  required bool Function() isCurrent,
}) async {
  final results = <(String, BhpanBatchStatus)>[];
  var stopped = false;
  for (final item in items) {
    if (!isCurrent()) return null;
    if (stopped) {
      results.add((item.name, BhpanBatchStatus.skipped));
      continue;
    }
    final result = await run(item);
    if (!isCurrent()) return null;
    final unknown =
        result?.error?.code == UbaaErrorCode.outcomeUnknown ||
        result?.result?.outcomeUnknown == true;
    final status = unknown
        ? BhpanBatchStatus.unknown
        : result == null
        ? BhpanBatchStatus.skipped
        : result.error != null || result.result?.success != true
        ? BhpanBatchStatus.failed
        : BhpanBatchStatus.done;
    results.add((item.name, status));
    stopped = unknown || result == null;
  }
  return results;
}

/// 批量结果卡片：先给汇总，展开后逐项列出，可手动关闭。
class BhpanBatchResults extends StatelessWidget {
  const BhpanBatchResults({
    super.key,
    required this.results,
    required this.onClose,
  });
  final List<(String, BhpanBatchStatus)> results;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    int count(BhpanBatchStatus s) => results.where((r) => r.$2 == s).length;
    final summary = [
      for (final s in BhpanBatchStatus.values)
        if (count(s) > 0) '${s.label} ${count(s)} 项',
    ].join('，');
    final attention = results.any((r) => r.$2 != BhpanBatchStatus.done);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      color: attention
          ? colors.tertiaryContainer.withValues(alpha: .5)
          : colors.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('bhpan-batch-results'),
          leading: Icon(
            attention ? Icons.info_outline : Icons.check_circle_outline,
            color: attention ? colors.tertiary : colors.primary,
          ),
          title: Text(summary, style: theme.textTheme.titleSmall),
          subtitle: attention ? const Text('结果待核对的操作请先刷新确认，不要重复提交') : null,
          trailing: IconButton(
            tooltip: '关闭',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
          initiallyExpanded: attention,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (name, status) in results)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '$name：${status.label}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 批量写入开头统一确认一次，列出将要处理的条目。
Future<bool> bhpanConfirmBatch(
  BuildContext context, {
  required BhpanMutationKind kind,
  required List<BhpanItem> items,
  String? destination,
  Widget Function(Widget)? boundary,
}) async {
  final (_, action, danger) = bhpanConfirmText(kind);
  final title = switch (kind) {
    BhpanMutationKind.recycle => '把 ${items.length} 项移入回收站？',
    BhpanMutationKind.restore => '恢复 ${items.length} 项？',
    BhpanMutationKind.deleteForever => '永久删除 ${items.length} 项？',
    BhpanMutationKind.move => '移动 ${items.length} 项？',
    BhpanMutationKind.copy => '复制 ${items.length} 项？',
    _ => '处理 ${items.length} 项？',
  };
  final shown = items.take(5).map((i) => i.name).toList();
  final dialog = Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      return AlertDialog(
        icon: danger
            ? Icon(Icons.warning_amber_rounded, color: colors.error)
            : null,
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final name in shown)
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  if (items.length > shown.length)
                    Text(
                      '等共 ${items.length} 项',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (destination != null) ...[
              const SizedBox(height: 12),
              Text('目标：$destination', style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            Text(
              [
                if (kind == BhpanMutationKind.deleteForever) '永久删除后无法找回。',
                if (items.length > 1) '会逐项提交，某一项结果不确定时停止后续操作。',
              ].join(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: kind == BhpanMutationKind.deleteForever
                    ? colors.error
                    : colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      );
    },
  );
  return await showDialog<bool>(
        context: context,
        builder: (_) => boundary == null ? dialog : boundary(dialog),
      ) ==
      true;
}

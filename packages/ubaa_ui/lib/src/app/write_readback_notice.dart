import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../shared/schedule_values.dart' show uiSavedScheduleTime;

/// 仅展示本机线索；查看记录或移除提示均不产生提交意图。
class WriteReadbackNotice extends StatefulWidget {
  const WriteReadbackNotice({
    required this.hints,
    required this.error,
    required this.onOpenFeature,
    this.onDismiss,
    this.onRefresh,
    super.key,
  });
  final List<WriteReadbackHint> hints;
  final UiError? error;
  final ValueChanged<FeatureId> onOpenFeature;
  final Future<void> Function(String)? onDismiss;
  final Future<void> Function()? onRefresh;

  @override
  State<WriteReadbackNotice> createState() => _WriteReadbackNoticeState();
}

class _WriteReadbackNoticeState extends State<WriteReadbackNotice> {
  final _removing = <String>{};
  final _failed = <String>{};

  Future<void> _dismiss(String id) async {
    final dismiss = widget.onDismiss;
    if (dismiss == null || _removing.contains(id)) return;
    setState(() {
      _removing.add(id);
      _failed.remove(id);
    });
    try {
      await dismiss(id);
    } on Object {
      if (mounted && widget.hints.any((hint) => hint.id == id))
        setState(() => _failed.add(id));
    } finally {
      if (mounted) setState(() => _removing.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    // 没有可显示的提醒、只是读取失败时，只占一行，不打扰首页。
    if (widget.hints.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('操作结果暂未同步'),
                    Text('最近的签到、选课或预约结果请到对应页面核对。', style: muted),
                  ],
                ),
              ),
              TextButton(onPressed: widget.onRefresh, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.help_outline_rounded, color: colors.tertiary),
          title: Text('${widget.hints.length} 项操作需要你确认结果'),
          subtitle: Text('提交时网络中断，学校可能已收到，也可能没有', style: muted),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('请到对应页面查看学校记录，确认后可关闭提醒；关闭提醒不会改变学校记录。', style: muted),
            if (widget.error != null)
              Row(
                children: [
                  Expanded(child: Text('另有部分操作结果暂未同步。', style: muted)),
                  TextButton(
                    onPressed: widget.onRefresh,
                    child: const Text('重试'),
                  ),
                ],
              ),
            for (final hint in widget.hints) ...[
              const Divider(),
              Text(
                hint.operation.title,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${hint.startedAt.toUtc().add(const Duration(hours: 8)).year}年'
                '${uiSavedScheduleTime(hint.startedAt)} · ${hint.route.label}',
                style: muted,
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: hint.feature == null
                        ? null
                        : () => widget.onOpenFeature(hint.feature!),
                    child: const Text('去查看'),
                  ),
                  TextButton(
                    onPressed:
                        widget.onDismiss == null || _removing.contains(hint.id)
                        ? null
                        : () => _dismiss(hint.id),
                    child: Text(
                      _removing.contains(hint.id) ? '正在关闭' : '已确认，关闭提醒',
                    ),
                  ),
                ],
              ),
              if (_failed.contains(hint.id))
                Text('没能关闭提醒，请重试', style: TextStyle(color: colors.error)),
            ],
          ],
        ),
      ),
    );
  }
}

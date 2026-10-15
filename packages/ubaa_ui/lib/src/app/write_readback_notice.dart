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
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      leading: const Icon(Icons.fact_check_outlined),
      title: Text(
        widget.hints.isEmpty ? '待核实提示暂不可用' : '${widget.hints.length} 次操作结果待核实',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('请核对学校记录；移除提示不会改变学校记录。'),
        if (widget.error != null) ...[
          const SizedBox(height: 8),
          const Text('本机待核实提示读取失败，已有提示仍保留。'),
          TextButton(onPressed: widget.onRefresh, child: const Text('重新读取提示')),
        ],
        for (final hint in widget.hints) ...[
          const Divider(),
          Text(hint.operation.title),
          Text(
            '${hint.startedAt.toUtc().add(const Duration(hours: 8)).year}年'
            '${uiSavedScheduleTime(hint.startedAt)} · ${hint.route.label}',
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => widget.onOpenFeature(hint.feature),
                child: const Text('查看相关记录'),
              ),
              TextButton(
                onPressed:
                    widget.onDismiss == null || _removing.contains(hint.id)
                    ? null
                    : () => _dismiss(hint.id),
                child: Text(
                  _removing.contains(hint.id) ? '正在移除' : '已核对，移除本机提示',
                ),
              ),
            ],
          ),
          if (_failed.contains(hint.id)) const Text('提示未能移除，请重试'),
        ],
      ],
    ),
  );
}

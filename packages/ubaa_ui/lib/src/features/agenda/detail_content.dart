import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'format.dart';

/// 窄屏面板与宽屏详情栏共用操作和本地备注输入。
class AgendaDetailContent extends StatefulWidget {
  const AgendaDetailContent({
    super.key,
    required this.entry,
    required this.conflicts,
    required this.onClose,
    required this.onEdit,
    required this.onDelete,
    required this.onComplete,
    required this.onSaveNote,
    required this.onHide,
    required this.onOpenSchool,
    this.busy = false,
  });
  final AgendaEntry entry;
  final List<AgendaEntry> conflicts;
  final VoidCallback onClose,
      onEdit,
      onDelete,
      onComplete,
      onHide,
      onOpenSchool;
  final ValueChanged<String> onSaveNote;
  final bool busy;
  @override
  State<AgendaDetailContent> createState() => _AgendaDetailContentState();
}

class _AgendaDetailContentState extends State<AgendaDetailContent> {
  late String note =
      widget.entry.note ?? widget.entry.local?.content.notes ?? '';
  @override
  Widget build(BuildContext context) {
    final entry = widget.entry, school = entry.school;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  agendaTitle(entry),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '关闭详情',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text('${agendaSource(entry)} · ${agendaWhen(entry)}'),
          Text(
            entry.timing.from ??
                (entry.timing.start ?? entry.timing.due)?.rfc3339.substring(
                  0,
                  10,
                ) ??
                '无日期',
          ),
          if (entry.local?.content.location ?? school?.location
              case final location?)
            Text(location),
          if (widget.conflicts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '与课程重叠：${widget.conflicts.map((e) => '${agendaTitle(e)} ${agendaWhen(e)}').join('、')}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (school != null) ...[
            const SizedBox(height: 12),
            Text('学校状态：${school.statusLabel}'),
            Text(school.subtitle),
            const Text('完成、隐藏与备注只保存在本机，不改变学校数据。'),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: note,
              onChanged: (value) => note = value,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '本地备注'),
            ),
            FilledButton(
              onPressed: widget.busy ? null : () => widget.onSaveNote(note),
              child: const Text('保存备注'),
            ),
            TextButton(
              onPressed: widget.busy ? null : widget.onOpenSchool,
              child: const Text('打开原功能'),
            ),
            TextButton(
              onPressed: widget.busy ? null : widget.onHide,
              child: Text(entry.hidden ? '恢复显示' : '隐藏事项'),
            ),
          ] else ...[
            if (entry.local?.content.notes case final notes?) Text(notes),
            TextButton(
              onPressed: widget.busy ? null : widget.onEdit,
              child: const Text('编辑事项'),
            ),
            TextButton(
              onPressed: widget.busy ? null : widget.onDelete,
              child: const Text('删除事项'),
            ),
          ],
          if (school?.navigation.feature != AgendaFeature.schedule &&
              school?.navigation.feature != AgendaFeature.exam)
            OutlinedButton(
              onPressed: widget.busy ? null : widget.onComplete,
              child: Text(entry.completed ? '重新挂起' : '标记完成'),
            ),
        ],
      ),
    );
  }
}

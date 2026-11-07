import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'calendar_values.dart';
import 'format.dart';
import '../../common/tag.dart';

/// 窄屏面板与宽屏详情栏共用操作和备注输入。
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
    this.displayEnd,
  });
  final AgendaEntry entry;

  /// 连续课程合并后的结束时间，与列表显示一致。
  final DateTime? displayEnd;
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
  late final String savedNote = widget.entry.note ?? '';
  late String note = savedNote;
  late bool editingNote = savedNote.isNotEmpty;

  String when(AgendaEntry entry) {
    final start = agendaStart(entry),
        end = widget.displayEnd ?? agendaEnd(entry);
    if (entry.timing.kind != AgendaTimingKind.period || start == null)
      return agendaWhen(entry);
    return '${agendaHm(start)} — ${end == null ? '结束时间待定' : agendaHm(end)}';
  }

  Widget row(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  /// 课程说明形如「2-3周,5-9周[实验]/杨海燕[主讲]」时拆为周次与教师。
  List<Widget> subtitleRows(SchoolAgendaItem school) {
    final text = school.subtitle.trim();
    if (text.isEmpty) return const [];
    final parts = text.split('/');
    if (school.navigation.feature == AgendaFeature.schedule &&
        parts.length == 2 &&
        parts.first.contains('周') &&
        parts.every((p) => p.trim().isNotEmpty)) {
      return [row('周次', parts.first.trim()), row('教师', parts.last.trim())];
    }
    return [row('说明', text)];
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry, school = entry.school;
    final theme = Theme.of(context);
    final date = agendaEntryDate(entry);
    final location = entry.local?.content.location ?? school?.location;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        12,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  agendaTitle(entry),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '关闭详情',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: UiTag(agendaSource(entry)),
          ),
          const SizedBox(height: 10),
          row('日期', date == null ? '无日期' : agendaMonthDayWeek(date)),
          row('时间', when(entry)),
          if (location != null && location.isNotEmpty) row('地点', location),
          if (school != null) ...[
            if (school.statusLabel != agendaSource(entry))
              row('状态', school.statusLabel),
            ...subtitleRows(school),
          ],
          if (widget.conflicts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '与课程重叠：${widget.conflicts.map((e) => '${agendaTitle(e)} ${agendaWhen(e)}').join('、')}',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (school != null) ...[
            const SizedBox(height: 12),
            if (editingNote) ...[
              TextFormField(
                initialValue: note,
                autofocus: savedNote.isEmpty,
                onChanged: (value) => setState(() => note = value),
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(labelText: '备注'),
              ),
              if (note != savedNote)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton(
                    onPressed: widget.busy
                        ? null
                        : () => widget.onSaveNote(note),
                    child: const Text('保存备注'),
                  ),
                ),
            ] else
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: widget.busy
                      ? null
                      : () => setState(() => editingNote = true),
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('添加备注'),
                ),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: widget.busy ? null : widget.onOpenSchool,
              child: const Text('查看原页面'),
            ),
            TextButton(
              onPressed: widget.busy ? null : widget.onHide,
              child: Text(entry.hidden ? '恢复显示' : '隐藏事项'),
            ),
          ] else ...[
            if (entry.local?.content.notes case final notes?
                when notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(notes),
              ),
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
              child: Text(entry.completed ? '标记未完成' : '标记完成'),
            ),
        ],
      ),
    );
  }
}

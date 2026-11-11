import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'calendar_values.dart';
import 'format.dart';
import '../../shared/dialogs/sheet.dart';
import 'list_content.dart' show agendaSourceColor;

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
    this.modal = false,
    this.displayEnd,
  });

  /// 模态底部面板里由拖动条关闭，不显示关闭按钮。
  final bool modal;
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

  /// 课程说明形如「2-3周,5-9周[实验]/杨海燕[主讲]」时拆为周次与教师。
  (String? weeks, String? teacher, String? other) splitSubtitle(
    SchoolAgendaItem school,
  ) {
    final text = school.subtitle.trim();
    if (text.isEmpty) return (null, null, null);
    final parts = text.split('/');
    if (school.navigation.feature == AgendaFeature.schedule &&
        parts.length == 2 &&
        parts.first.contains('周') &&
        parts.every((p) => p.trim().isNotEmpty)) {
      return (
        agendaWeeksLabel(parts.first.trim()),
        agendaTeacherLabel(parts.last.trim()),
        null,
      );
    }
    return (null, null, text);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry, school = entry.school;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final date = agendaEntryDate(entry);
    final location = entry.local?.content.location ?? school?.location;
    final (weeks, teacher, other) = school == null
        ? (null, null, null)
        : splitSubtitle(school);
    final source = agendaSource(entry);
    final status = school != null && school.statusLabel != source
        ? school.statusLabel
        : null;
    final completable =
        school?.navigation.feature != AgendaFeature.schedule &&
        school?.navigation.feature != AgendaFeature.exam;
    final busy = widget.busy;
    final danger = OutlinedButton.styleFrom(foregroundColor: colors.error);
    return UiSheetBody(
      title: agendaTitle(entry),
      subtitle: [source, ?weeks].join(' · '),
      accent: agendaSourceColor(entry, colors),
      onClose: widget.modal ? null : widget.onClose,
      children: [
        UiInfoRow(
          icon: Icons.schedule,
          text: [
            date == null ? '无日期' : agendaMonthDayWeek(date),
            when(entry),
          ].join(' · '),
        ),
        if (location != null && location.isNotEmpty)
          UiInfoRow(icon: Icons.place_outlined, text: location),
        if (teacher != null)
          UiInfoRow(icon: Icons.person_outline, text: teacher),
        if (other != null) UiInfoRow(icon: Icons.notes, text: other),
        if (status != null) UiInfoRow(icon: Icons.info_outline, text: status),
        if (widget.conflicts.isNotEmpty)
          UiInfoRow(
            icon: Icons.warning_amber_rounded,
            color: colors.error,
            text:
                '与课程重叠：${widget.conflicts.map((e) => '${agendaTitle(e)} ${agendaWhen(e)}').join('、')}',
          ),
        if (school == null)
          if (entry.local?.content.notes case final notes?
              when notes.isNotEmpty)
            UiInfoRow(icon: Icons.notes, text: notes),
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
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton(
                    onPressed: busy ? null : () => widget.onSaveNote(note),
                    child: const Text('保存备注'),
                  ),
                ),
              ),
          ] else
            UiSheetPlaceholderField(
              icon: Icons.edit_note_outlined,
              label: '添加备注…',
              onTap: busy ? null : () => setState(() => editingNote = true),
            ),
        ],
      ],
      actions: [
        if (school != null) ...[
          OutlinedButton(
            onPressed: busy ? null : widget.onOpenSchool,
            child: const Text('查看原页面'),
          ),
          OutlinedButton(
            onPressed: busy ? null : widget.onHide,
            child: Text(entry.hidden ? '恢复显示' : '隐藏事项'),
          ),
        ] else ...[
          OutlinedButton(
            onPressed: busy ? null : widget.onEdit,
            child: const Text('编辑事项'),
          ),
          OutlinedButton(
            style: danger,
            onPressed: busy ? null : widget.onDelete,
            child: const Text('删除事项'),
          ),
        ],
      ],
      primaryAction: completable
          ? FilledButton(
              onPressed: busy ? null : widget.onComplete,
              child: Text(entry.completed ? '标记未完成' : '标记完成'),
            )
          : null,
    );
  }
}

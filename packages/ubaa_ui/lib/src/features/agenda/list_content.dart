import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'calendar_values.dart';
import 'format.dart';

class AgendaListContent extends StatelessWidget {
  const AgendaListContent({
    super.key,
    required this.entries,
    required this.allEntries,
    required this.now,
    required this.onOpen,
    required this.onComplete,
    this.busy = false,
  });
  final List<AgendaEntry> entries, allEntries;
  final DateTime now;
  final ValueChanged<AgendaEntry> onOpen;
  final void Function(AgendaEntry, bool) onComplete;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final groups = <String, List<AgendaEntry>>{};
    for (final entry in entries) {
      final date = agendaEntryDate(entry);
      final overdue =
          !entry.completed &&
          entry.timing.kind == AgendaTimingKind.deadline &&
          agendaValue(entry.timing.due)?.isBefore(now) == true;
      final key = overdue
          ? '逾期待办'
          : date == null
          ? '无日期'
          : agendaDate(date);
      (groups[key] ??= []).add(entry);
    }
    final keys = groups.keys.toList()
      ..sort(
        (a, b) => a == '逾期待办'
            ? -1
            : b == '逾期待办'
            ? 1
            : a.compareTo(b),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text('当前范围没有符合筛选的事项，可新建日程或待办', textAlign: TextAlign.center),
          ),
        for (final day in keys) ...[
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8),
            child: Text(day, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final entry
              in (groups[day]!..sort((a, b) {
                final allA = a.timing.kind == AgendaTimingKind.allDay,
                    allB = b.timing.kind == AgendaTimingKind.allDay;
                return allA != allB
                    ? (allA ? -1 : 1)
                    : (agendaEntryDate(a)?.toIso8601String() ?? '').compareTo(
                        agendaEntryDate(b)?.toIso8601String() ?? '',
                      );
              })))
            AgendaEntryTile(
              entry: entry,
              conflicts: agendaEntryConflicts(entry, allEntries),
              onOpen: () => onOpen(entry),
              busy: busy,
              onComplete: (v) => onComplete(entry, v),
            ),
        ],
      ],
    );
  }
}

class AgendaEntryTile extends StatelessWidget {
  const AgendaEntryTile({
    super.key,
    required this.entry,
    required this.onOpen,
    required this.onComplete,
    this.conflicts = const [],
    this.busy = false,
  });
  final AgendaEntry entry;
  final List<AgendaEntry> conflicts;
  final VoidCallback onOpen;
  final ValueChanged<bool> onComplete;
  final bool busy;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(
        entry.local == null
            ? Icons.school_outlined
            : entry.local!.content.kind == AgendaKind.task
            ? Icons.check_circle_outline
            : Icons.event_outlined,
        color: agendaColor(entry.local?.content.color),
      ),
      title: Text(
        agendaTitle(entry),
        style: TextStyle(
          decoration: entry.completed ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        '${agendaSource(entry)} · ${agendaWhen(entry)}${entry.hidden ? ' · 已隐藏' : ''}\n${entry.local?.content.location ?? entry.school?.location ?? ''}${entry.note?.isNotEmpty == true ? ' · ${entry.note}' : ''}${conflicts.isEmpty ? '' : '\n与课程重叠：${conflicts.map(agendaTitle).toSet().join('、')}'}',
      ),
      trailing:
          entry.school?.navigation.feature == AgendaFeature.schedule ||
              entry.school?.navigation.feature == AgendaFeature.exam
          ? null
          : Checkbox(
              value: entry.completed,
              onChanged: busy ? null : (v) => onComplete(v!),
            ),
      onTap: onOpen,
      onLongPress: onOpen,
    ),
  );
}

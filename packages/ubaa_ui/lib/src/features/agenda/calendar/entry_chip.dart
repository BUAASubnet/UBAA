import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../../shared/dialogs/sheet.dart' show showUiSheet, UiSheetBody;
import '../format.dart';
import '../list_content.dart' show agendaSourceColor;

/// 周视图全天行与月网格共用的事项条：来源色浅底加左侧色条，与周网格课程块一致。
class AgendaEntryChip extends StatelessWidget {
  const AgendaEntryChip({
    super.key,
    required this.entry,
    required this.label,
    required this.onTap,
    this.conflict = false,
    this.wrap = false,
  });
  final AgendaEntry entry;
  final String label;
  final VoidCallback onTap;

  /// 与课程重叠时描红边，完整说明放在提示与读屏标签里。
  final bool conflict;

  /// 窄列允许两行，不加省略号。
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final source = agendaSourceColor(entry, colors);
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Tooltip(
        message:
            '${agendaTitle(entry)} · ${agendaWhen(entry)}${conflict ? ' · 与课程重叠' : ''}',
        child: Material(
          color: Color.alphaBlend(
            source.withValues(alpha: entry.completed ? .1 : .22),
            colors.surfaceContainerLow,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: conflict ? BorderSide(color: colors.error) : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ColoredBox(color: source, child: const SizedBox(width: 3)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 2, 3, 2),
                      child: Text(
                        label,
                        maxLines: wrap ? 2 : 1,
                        overflow: wrap
                            ? TextOverflow.clip
                            : TextOverflow.ellipsis,
                        softWrap: wrap,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: entry.completed
                              ? colors.onSurfaceVariant
                              : colors.onSurface,
                          decoration: entry.completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 某天（或无日期）事项太多放不下时，点「+N」列出全部。
Future<void> showAgendaEntryList(
  BuildContext context, {
  required String title,
  required List<AgendaEntry> entries,
  required ValueChanged<AgendaEntry> onOpen,
}) => showUiSheet<void>(
  context,
  builder: (sheet) => UiSheetBody(
    title: title,
    subtitle: '${entries.length} 项',
    children: [
      for (final entry in entries)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.circle,
            size: 10,
            color: agendaSourceColor(entry, Theme.of(sheet).colorScheme),
          ),
          title: Text(agendaTitle(entry)),
          subtitle: Text(agendaWhen(entry)),
          onTap: () {
            Navigator.pop(sheet);
            onOpen(entry);
          },
        ),
    ],
  ),
);

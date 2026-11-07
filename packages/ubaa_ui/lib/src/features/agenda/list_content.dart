import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'calendar_values.dart';
import 'format.dart';
import '../../common/state_panel.dart';
import '../../common/tag.dart';

/// 列表分组标题：今天/明天/昨天优先，其余显示「11月5日 周四」。
String agendaDayLabel(DateTime day, DateTime now) {
  final today = agendaDay(now);
  final diff = agendaDay(day).difference(today).inDays;
  final date = agendaMonthDayWeek(day);
  return switch (diff) {
    0 => '今天 · $date',
    1 => '明天 · $date',
    -1 => '昨天 · $date',
    _ => date,
  };
}

List<Widget> agendaListSlivers({
  required BuildContext context,
  required List<AgendaEntry> entries,
  required List<AgendaEntry> allEntries,
  required DateTime now,
  required ValueChanged<AgendaEntry> onOpen,
  required void Function(AgendaEntry, bool) onComplete,
  VoidCallback? onCreate,
  bool busy = false,

  /// 月视图选中某天时，空日只显示一行说明，新建入口由悬浮按钮承担。
  String? compactEmpty,
}) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  if (entries.isEmpty && compactEmpty != null) {
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        sliver: SliverToBoxAdapter(
          child: Text(
            compactEmpty,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    ];
  }
  if (entries.isEmpty) {
    return [
      SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 64),
          child: UiStatePanel(
            icon: Icons.wb_twilight_rounded,
            title: '这段时间没有安排',
            detail: '没有符合筛选的事项，可新建日程或待办',
            action: '新建事项',
            actionIcon: Icons.add,
            onAction: onCreate,
          ),
        ),
      ),
    ];
  }
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
  final todayKey = agendaDate(agendaDay(now));
  return [
    for (final day in keys) ...[
      SliverPersistentHeader(
        pinned: true,
        delegate: _AgendaDayHeader(
          label: day == '逾期待办' || day == '无日期'
              ? day
              : agendaDayLabel(DateTime.parse(day), now),
          count: agendaAttachSignins(agendaMergeCourses(groups[day]!)).length,
          overdue: day == '逾期待办',
          today: day == todayKey,
          colors: colors,
          style: theme.textTheme.titleSmall!,
          height: MediaQuery.textScalerOf(context).scale(16) + 28,
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        sliver: SliverList.list(
          children: [
            for (final (entry, end, signin) in agendaAttachSignins(
              agendaMergeCourses(
                groups[day]!..sort((a, b) {
                  final allA = a.timing.kind == AgendaTimingKind.allDay,
                      allB = b.timing.kind == AgendaTimingKind.allDay;
                  return allA != allB
                      ? (allA ? -1 : 1)
                      : (agendaEntryDate(a)?.toIso8601String() ?? '').compareTo(
                          agendaEntryDate(b)?.toIso8601String() ?? '',
                        );
                }),
              ),
            ))
              AgendaEntryTile(
                entry: entry,
                now: now,
                displayEnd: end,
                signin: signin,
                onOpenSignin: signin == null ? null : () => onOpen(signin),
                conflicts: agendaEntryConflicts(entry, allEntries),
                onOpen: () => onOpen(entry),
                busy: busy,
                onComplete: (value) => onComplete(entry, value),
              ),
          ],
        ),
      ),
    ],
  ];
}

class _AgendaDayHeader extends SliverPersistentHeaderDelegate {
  _AgendaDayHeader({
    required this.label,
    required this.count,
    required this.overdue,
    required this.today,
    required this.colors,
    required this.style,
    required this.height,
  });
  final String label;
  final int count;
  final bool overdue, today;
  final ColorScheme colors;
  final TextStyle style;
  final double height;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final accent = overdue
        ? colors.error
        : today
        ? colors.primary
        : colors.onSurfaceVariant;
    return SizedBox.expand(
      child: ColoredBox(
        color: colors.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            children: [
              if (today || overdue)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Text(
                  label,
                  style: style.copyWith(
                    color: accent,
                    fontWeight: today || overdue
                        ? FontWeight.w700
                        : FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$count 项',
                style: style.copyWith(
                  color: colors.outline,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_AgendaDayHeader oldDelegate) =>
      label != oldDelegate.label ||
      count != oldDelegate.count ||
      today != oldDelegate.today ||
      colors != oldDelegate.colors ||
      height != oldDelegate.height ||
      style != oldDelegate.style;
}

/// 来源色：自建事项用用户颜色，学校事项按来源区分。
Color agendaSourceColor(AgendaEntry entry, ColorScheme colors) =>
    agendaColor(entry.local?.content.color) ??
    switch (entry.school?.navigation.feature) {
      AgendaFeature.schedule => colors.primary,
      AgendaFeature.spoc || AgendaFeature.judge => const Color(0xFFE8833A),
      AgendaFeature.exam => colors.error,
      AgendaFeature.bykc => const Color(0xFF8E5CD9),
      AgendaFeature.cgyy => const Color(0xFF2E9E8F),
      _ => colors.tertiary,
    };

IconData agendaSourceIcon(AgendaEntry entry) => entry.local != null
    ? (entry.local!.content.kind == AgendaKind.task
          ? Icons.check_circle_outline
          : Icons.event_note_outlined)
    : switch (entry.school?.navigation.feature) {
        AgendaFeature.schedule => Icons.menu_book_outlined,
        AgendaFeature.spoc || AgendaFeature.judge => Icons.assignment_outlined,
        AgendaFeature.exam => Icons.edit_note_outlined,
        AgendaFeature.bykc => Icons.theater_comedy_outlined,
        AgendaFeature.cgyy => Icons.meeting_room_outlined,
        _ => Icons.notifications_none_outlined,
      };

class AgendaEntryTile extends StatelessWidget {
  const AgendaEntryTile({
    super.key,
    required this.entry,
    required this.onOpen,
    required this.onComplete,
    this.now,
    this.conflicts = const [],
    this.busy = false,
    this.displayEnd,
    this.signin,
    this.onOpenSignin,
  });
  final AgendaEntry entry;
  final DateTime? now;
  final List<AgendaEntry> conflicts;
  final VoidCallback onOpen;
  final ValueChanged<bool> onComplete;
  final bool busy;

  /// 合并连续课程后的显示结束时间。
  final DateTime? displayEnd;

  /// 归入本课程的签到条目。
  final AgendaEntry? signin;
  final VoidCallback? onOpenSignin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = agendaSourceColor(entry, colors);
    final location = entry.local?.content.location ?? entry.school?.location;
    final label = entry.hidden
        ? '已隐藏'
        : entry.completed
        ? '已完成'
        : entry.school?.statusLabel;
    final start = agendaStart(entry), end = displayEnd ?? agendaEnd(entry);
    final due = agendaValue(entry.timing.due);
    final ended =
        now != null &&
        (entry.completed ||
            (end != null && end.isBefore(now!)) ||
            (end == null &&
                due != null &&
                due.isBefore(now!) &&
                entry.completed));
    final checkable =
        !(entry.school?.navigation.feature == AgendaFeature.schedule ||
            entry.school?.navigation.feature == AgendaFeature.exam);
    final (String top, String? bottom) = switch (entry.timing.kind) {
      AgendaTimingKind.allDay => ('全天', null),
      AgendaTimingKind.deadline when due != null => (agendaHm(due), '截止'),
      _ when start != null => (
        agendaHm(start),
        end == null ? null : agendaHm(end),
      ),
      _ => ('—', null),
    };
    final meta = [
      if (location?.isNotEmpty == true) location!,
      agendaSource(entry),
    ].join(' · ');
    return Opacity(
      opacity: ended ? .55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 48,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      top,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (bottom != null)
                      Text(
                        bottom,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Material(
                color: Color.alphaBlend(
                  color.withValues(alpha: .07),
                  colors.surfaceContainerLow,
                ),
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onOpen,
                  onLongPress: onOpen,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: 4,
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  agendaTitle(entry),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                    decoration: entry.completed
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      agendaSourceIcon(entry),
                                      size: 14,
                                      color: color,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        meta,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (entry.note?.isNotEmpty == true)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      entry.note!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                if (conflicts.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '与课程重叠：${conflicts.map(agendaTitle).toSet().join('、')}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: colors.error),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (signin case final s?)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _SigninPill(
                                    signin: s,
                                    onTap: onOpenSignin,
                                  ),
                                )
                              else if (checkable)
                                Checkbox(
                                  value: entry.completed,
                                  shape: const CircleBorder(),
                                  onChanged: busy
                                      ? null
                                      : (value) => onComplete(value!),
                                )
                              else if (label?.isNotEmpty == true &&
                                  label != agendaSource(entry))
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: _StatusPill(
                                    label: label!,
                                    color: color,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => UiTag(label, color: color);
}

class _SigninPill extends StatelessWidget {
  const _SigninPill({required this.signin, this.onTap});
  final AgendaEntry signin;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final done =
        signin.completed || signin.school?.upstreamStatus.completed == true;
    final status = signin.school?.statusLabel ?? '';
    final label = done ? '已签到' : (status.contains('签到') ? status : '签到');
    final (fg, bg) = UiTag.colorsOf(
      context,
      tone: done ? UiTagTone.primary : UiTagTone.neutral,
      color: done ? null : colors.primary,
    );
    return Semantics(
      button: true,
      label: '课程签到：$label',
      excludeSemantics: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(UiTag.radius),
        child: InkWell(
          key: ValueKey('agenda-signin-${agendaEntryKey(signin)}'),
          borderRadius: BorderRadius.circular(UiTag.radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  done ? Icons.check_circle : Icons.how_to_reg_outlined,
                  size: 14,
                  color: fg,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

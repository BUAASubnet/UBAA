import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../theme.dart' show UbaaTheme;

/// 学校各来源的最近更新时间；面向学生只区分「X 前更新」与「更新失败」。
class AgendaCacheStatus extends StatelessWidget {
  const AgendaCacheStatus({
    super.key,
    required this.sources,
    required this.now,
  });
  final List<AgendaSource> sources;
  final AgendaTime now;

  String name(AgendaFeature feature) => switch (feature) {
    AgendaFeature.schedule => '课程',
    AgendaFeature.exam => '考试',
    AgendaFeature.bykc => '博雅',
    AgendaFeature.spoc => 'SPOC作业',
    AgendaFeature.judge => '希冀作业',
    AgendaFeature.signin => '签到',
    AgendaFeature.cgyy => '研讨室',
    AgendaFeature.ygdk => '阳光打卡',
  };

  String ago(int seconds) {
    final diff =
        DateTime.parse(now.rfc3339).millisecondsSinceEpoch ~/ 1000 - seconds;
    if (diff < 60) return '刚刚';
    if (diff < 3600) return '${diff ~/ 60} 分钟前';
    if (diff < 86400) return '${diff ~/ 3600} 小时前';
    return '${diff ~/ 86400} 天前';
  }

  /// 最近一次成功向学校确认的时间：内容未变化时核验时间不前进，但确认已完成。
  int checkedAt(Iterable<AgendaObservation> observations) => observations
      .map(
        (o) => o.lastAttemptSucceeded && o.lastAttemptAt > o.lastVerifiedAt
            ? o.lastAttemptAt
            : o.lastVerifiedAt,
      )
      .reduce((a, b) => a > b ? a : b);

  String freshness(Iterable<AgendaObservation> observations) =>
      '${ago(checkedAt(observations))}更新';

  bool failed(AgendaSource source) =>
      source.observations.any((o) => !o.lastAttemptSucceeded);

  /// 概要：最近更新时间，以及上次更新失败的来源。
  String friendly(List<AgendaObservation> observations) {
    final failing = [
      for (final source in sources)
        if (source.observations.isNotEmpty && failed(source))
          name(source.feature),
    ];
    return [
      freshness(observations),
      if (failing.isNotEmpty) '${failing.join('、')}更新失败',
    ].join(' · ');
  }

  IconData icon(AgendaFeature feature) => switch (feature) {
    AgendaFeature.schedule => Icons.menu_book_outlined,
    AgendaFeature.exam => Icons.edit_note_outlined,
    AgendaFeature.bykc => Icons.theater_comedy_outlined,
    AgendaFeature.spoc => Icons.assignment_outlined,
    AgendaFeature.judge => Icons.code_rounded,
    AgendaFeature.signin => Icons.how_to_reg_outlined,
    AgendaFeature.cgyy => Icons.meeting_room_outlined,
    AgendaFeature.ygdk => Icons.directions_run_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final observations = sources.expand((s) => s.observations).toList();
    if (observations.isEmpty) return const SizedBox.shrink();
    final summary = friendly(observations);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final good = UbaaTheme.success(colors);
    final amber = UbaaTheme.warning(colors);
    return Container(
      key: const ValueKey('agenda-cache-status'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '学校数据',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          for (final source in sources)
            if (source.observations.isNotEmpty)
              Builder(
                builder: (context) {
                  final issue = failed(source);
                  return ListTile(
                    key: ValueKey('agenda-cache-${source.feature.name}'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    dense: true,
                    leading: Icon(
                      icon(source.feature),
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                    title: Text(
                      name(source.feature),
                      style: theme.textTheme.bodyMedium,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: issue ? amber : good,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          issue ? '更新失败' : freshness(source.observations),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: issue ? amber : colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

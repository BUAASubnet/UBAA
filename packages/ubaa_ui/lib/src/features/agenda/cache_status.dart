import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../theme.dart' show UbaaTheme;

/// 保留各来源和查询范围的缓存状态，时间统一显示为北京时间。
class AgendaCacheStatus extends StatelessWidget {
  const AgendaCacheStatus({
    super.key,
    required this.sources,
    required this.route,
    required this.now,
  });
  final List<AgendaSource> sources;
  final ConnectionMode route;
  final AgendaTime now;

  String time(int seconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    ).add(const Duration(hours: 8));
    return date.toIso8601String().substring(0, 16).replaceFirst('T', ' ');
  }

  String range(Iterable<int> seconds) {
    final values = seconds.toList()..sort();
    return values.first == values.last
        ? time(values.first)
        : '${time(values.first)} — ${time(values.last)}';
  }

  String name(AgendaFeature feature) => switch (feature) {
    AgendaFeature.schedule => '课程',
    AgendaFeature.exam => '考试',
    AgendaFeature.bykc => '博雅',
    AgendaFeature.spoc => 'SPOC作业',
    AgendaFeature.judge => '希冀作业',
    AgendaFeature.signin => '签到',
    AgendaFeature.cgyy => '研讨室',
    AgendaFeature.ygdk => '阳光提醒',
  };

  String status(List<AgendaObservation> observations) => [
    if (observations.any(
      (o) =>
          DateTime.parse(now.rfc3339).millisecondsSinceEpoch ~/ 1000 -
              o.lastVerifiedAt >
          300,
    ))
      '核验已超过5分钟',
    if (observations.any((o) => !o.lastAttemptSucceeded)) '上次更新失败',
    if (observations.any((o) => o.completeness == AgendaCompleteness.partial))
      '部分结果',
    if (observations.any(
      (o) => o.lastAttemptSucceeded && o.lastAttemptAt != o.lastVerifiedAt,
    ))
      '最近更新尚未核验',
  ].join(' · ');

  String scope(AgendaCacheScope scope) => [
    if (scope.term?.isNotEmpty == true) scope.term!,
    if (scope.week != null) '第${scope.week}教学周',
    if (scope.date != null) scope.date!,
    if (scope.weekStart != null) '周起始 ${scope.weekStart}',
    if (scope.page != null) '第${scope.page}页',
    if (scope.kind == AgendaCacheKind.importedSchedules) '整学期课表',
    if (scope.kind == AgendaCacheKind.scheduleWeeks) '教学周索引',
  ].join(' · ');

  String ago(int seconds) {
    final diff =
        DateTime.parse(now.rfc3339).millisecondsSinceEpoch ~/ 1000 - seconds;
    if (diff < 60) return '刚刚';
    if (diff < 3600) return '${diff ~/ 60} 分钟前';
    if (diff < 86400) return '${diff ~/ 3600} 小时前';
    return time(seconds);
  }

  /// 最近一次成功检查的时间：复用缓存时核验时间不变，但检查已完成。
  int checkedAt(Iterable<AgendaObservation> observations) => observations
      .map(
        (o) => o.lastAttemptSucceeded && o.lastAttemptAt > o.lastVerifiedAt
            ? o.lastAttemptAt
            : o.lastVerifiedAt,
      )
      .reduce((a, b) => a > b ? a : b);

  int verifiedAt(Iterable<AgendaObservation> observations) =>
      observations.map((o) => o.lastVerifiedAt).reduce((a, b) => a > b ? a : b);

  /// 「检查」表示已向学校确认但内容沿用缓存；「更新」表示取得了新内容。
  String freshness(Iterable<AgendaObservation> observations) {
    final checked = checkedAt(observations),
        verified = verifiedAt(observations);
    return checked - verified > 60 ? '${ago(checked)}检查' : '${ago(verified)}更新';
  }

  /// 面向用户的概要：最近更新时间与需要关注的来源；技术细节在展开项中。
  String friendly(List<AgendaObservation> observations) {
    // 「尝试未成功」也可能只是本次结果不完整，不能据此断言请求失败。
    final pending = [
      for (final source in sources)
        if (source.observations.any(
          (o) =>
              !o.lastAttemptSucceeded ||
              o.completeness == AgendaCompleteness.partial,
        ))
          name(source.feature),
    ];
    return [
      freshness(observations),
      if (pending.isNotEmpty) '${pending.join('、')}待补全',
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
                  '学校数据（${route == ConnectionMode.direct ? '直连' : 'WebVPN'}）',
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
                  final issue = source.observations.any(
                    (o) =>
                        !o.lastAttemptSucceeded ||
                        o.completeness == AgendaCompleteness.partial,
                  );
                  final tone = issue ? amber : good;
                  return Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: ValueKey('agenda-cache-${source.feature.name}'),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                              color: tone,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            issue ? '待补全' : freshness(source.observations),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: issue ? amber : colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.expand_more,
                            size: 18,
                            color: colors.outline,
                          ),
                        ],
                      ),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            name(source.feature),
                            status(source.observations),
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: theme.textTheme.labelMedium,
                        ),
                        Text(
                          '保存 ${range(source.observations.map((o) => o.fetchedAt))}\n核验 ${range(source.observations.map((o) => o.lastVerifiedAt))}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        for (final observation in source.observations)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  scope(observation.scope).isEmpty
                                      ? '当前范围'
                                      : scope(observation.scope),
                                  style: theme.textTheme.labelMedium,
                                ),
                                Text(
                                  '保存 ${time(observation.fetchedAt)}\n核验 ${time(observation.lastVerifiedAt)}\n尝试 ${time(observation.lastAttemptAt)} · ${status([observation]).isEmpty ? '完整结果' : status([observation])}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
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

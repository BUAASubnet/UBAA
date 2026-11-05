import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

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

  /// 面向用户的概要：最近更新时间与需要关注的来源；技术细节在展开项中。
  String friendly(List<AgendaObservation> observations) {
    final latest = observations
        .map((o) => o.lastVerifiedAt)
        .reduce((a, b) => a > b ? a : b);
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
      '${ago(latest)}更新',
      if (pending.isNotEmpty) '${pending.join('、')}待补全',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final observations = sources.expand((s) => s.observations).toList();
    if (observations.isEmpty) return const SizedBox.shrink();
    final summary = friendly(observations);
    return ExpansionTile(
      key: const ValueKey('agenda-cache-status'),
      tilePadding: EdgeInsets.zero,
      title: Text('学校数据（${route == ConnectionMode.direct ? '直连' : 'WebVPN'}）'),
      subtitle: Text(summary),
      children: [
        for (final source in sources)
          if (source.observations.isNotEmpty)
            ExpansionTile(
              key: ValueKey('agenda-cache-${source.feature.name}'),
              tilePadding: EdgeInsets.zero,
              title: Text(
                [
                  name(source.feature),
                  status(source.observations),
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
              subtitle: Text(
                '保存 ${range(source.observations.map((o) => o.fetchedAt))}\n核验 ${range(source.observations.map((o) => o.lastVerifiedAt))}',
              ),
              children: [
                for (final observation in source.observations)
                  ListTile(
                    title: Text(
                      scope(observation.scope).isEmpty
                          ? '当前范围'
                          : scope(observation.scope),
                    ),
                    subtitle: Text(
                      '保存 ${time(observation.fetchedAt)}\n核验 ${time(observation.lastVerifiedAt)}\n尝试 ${time(observation.lastAttemptAt)} · ${status([observation]).isEmpty ? '完整结果' : status([observation])}',
                    ),
                  ),
              ],
            ),
      ],
    );
  }
}

import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:flutter/material.dart';
import '../../shared/feedback.dart';

String? homeSyncNotice(HomeState? home) {
  if (home == null) return null;
  if (home.offline) return '离线，显示已保存数据';
  final snapshots = [...home.sources.values, home.schedule.snapshot];
  if (home.week?.error != null ||
      snapshots.any(
        (s) => s.error != null || s.status == FeatureLoadStatus.failure,
      )) {
    return '部分更新失败';
  }
  final evidence = [
    home.week?.evidence,
    for (final snapshot in snapshots) snapshot.evidence,
  ].nonNulls;
  if (home.sources[FeatureId.judge]?.refining ?? false) return '正在更新希冀作业';
  if (home.busy || snapshots.any((s) => s.status == FeatureLoadStatus.loading))
    return null;
  if (evidence.any((e) => !e.complete)) return '部分数据未更新完整';
  if (snapshots.any((s) => s.status == FeatureLoadStatus.stale)) {
    return '部分数据使用缓存';
  }
  return null;
}

void showHomeSyncDetails(BuildContext context, HomeState home) {
  String status(FeatureSnapshot snapshot) {
    if (snapshot.error case final error?) return '更新失败：${error.title}';
    if (snapshot.status == FeatureLoadStatus.failure) return '更新失败';
    if (snapshot.refining || snapshot.status == FeatureLoadStatus.loading)
      return '正在更新';
    if (snapshot.evidence?.complete == false) return '部分数据未更新完整';
    return switch (snapshot.evidence?.origin) {
      DataOrigin.persisted => '显示已保存数据',
      DataOrigin.mixed => '更新完成，包含有效缓存',
      DataOrigin.online => '更新完成',
      null => snapshot.status == FeatureLoadStatus.empty ? '暂无数据' : '尚未更新',
    };
  }

  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('首页更新状态'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final snapshot in [
              ...home.sources.values,
              home.schedule.snapshot,
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('${snapshot.feature.title}：${status(snapshot)}'),
              ),
            if (home.week case final week?)
              Text(
                '当前教学周：${week.error?.title ?? (week.evidence?.complete == false ? '部分数据未更新完整' : '已取得数据')}',
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

Future<void> importAgendaSchedule(
  BuildContext context,
  String term,
  Future<void> Function(String)? save,
  VoidCallback openSchedule,
  Future<void> Function(Future<void> Function()) join,
) async {
  if (term.trim().isEmpty || save == null) {
    openSchedule();
    return;
  }
  try {
    await join(() => save(term));
  } on Object {
    if (context.mounted) {
      UbaaFeedback.show(context, '课表导入失败，请重试', kind: UbaaFeedbackKind.error);
    }
  }
}

Future<void> joinUiRefresh(
  Map<Object, Future<void>> pending,
  Object key,
  Future<void> Function() action,
) {
  final existing = pending[key];
  if (existing != null) return existing;
  late final Future<void> refresh;
  refresh = Future<void>.sync(action).whenComplete(() {
    if (identical(pending[key], refresh)) pending.remove(key);
  });
  pending[key] = refresh;
  return refresh;
}

YgdkReminderSettings? observedReminderProgress(
  YgdkReminderSettings? current,
  WeekPresentation week,
  YgdkOverview overview,
) {
  if (current == null ||
      !current.enabled ||
      !week.current ||
      week.responseTerm.trim().isEmpty)
    return null;
  final weekKey = '${week.responseTerm}:${week.number}';
  final weekDone =
      (overview.weekCount ?? -1) >= 4 && current.weekDoneKey != weekKey;
  final termDone =
      overview.termCount >= 16 && current.termDoneKey != week.responseTerm;
  return !weekDone && !termDone
      ? null
      : current.copyWith(
          weekDoneKey: weekDone ? weekKey : null,
          termDoneKey: termDone ? week.responseTerm : null,
        );
}

FeatureReadNavigation gradeNoticeTarget(GradeScoreNotice notice) =>
    FeatureReadNavigation(
      feature: FeatureId.grades,
      query: FeatureQuery(term: notice.termCode),
    );
ConnectionMode agendaRoute(
  RoutePolicy policy,
  List<ConnectionMode> active, {
  ConnectionMode? schoolRoute,
}) => switch (policy) {
  RoutePolicy.direct => ConnectionMode.direct,
  RoutePolicy.webvpn => ConnectionMode.webvpn,
  RoutePolicy.auto =>
    schoolRoute ??
        (active.contains(ConnectionMode.direct)
            ? ConnectionMode.direct
            : active.contains(ConnectionMode.webvpn)
            ? ConnectionMode.webvpn
            : ConnectionMode.direct),
};

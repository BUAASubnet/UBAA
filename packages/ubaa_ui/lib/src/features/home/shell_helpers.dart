import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:flutter/material.dart';
import '../../shared/feedback.dart';

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

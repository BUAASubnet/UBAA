import 'package:ubaa_domain/ubaa_domain.dart';

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
ConnectionMode agendaRoute(RoutePolicy policy, List<ConnectionMode> active) =>
    switch (policy) {
      RoutePolicy.direct => ConnectionMode.direct,
      RoutePolicy.webvpn => ConnectionMode.webvpn,
      RoutePolicy.auto =>
        active.contains(ConnectionMode.direct)
            ? ConnectionMode.direct
            : active.contains(ConnectionMode.webvpn)
            ? ConnectionMode.webvpn
            : ConnectionMode.direct,
    };

import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'models.dart';

AgendaFeature fromAgendaFeature(BridgeAgendaFeature v) => switch (v) {
  BridgeAgendaFeature.bykc => AgendaFeature.bykc,
  BridgeAgendaFeature.spoc => AgendaFeature.spoc,
  BridgeAgendaFeature.judge => AgendaFeature.judge,
  BridgeAgendaFeature.cgyy => AgendaFeature.cgyy,
  BridgeAgendaFeature.signin => AgendaFeature.signin,
  BridgeAgendaFeature.exam => AgendaFeature.exam,
  BridgeAgendaFeature.ygdk => AgendaFeature.ygdk,
  BridgeAgendaFeature.schedule => AgendaFeature.schedule,
};
AgendaTimingKind fromAgendaTimingKind(BridgeAgendaTimingKind v) => switch (v) {
  BridgeAgendaTimingKind.period => AgendaTimingKind.period,
  BridgeAgendaTimingKind.deadline => AgendaTimingKind.deadline,
  BridgeAgendaTimingKind.allDay => AgendaTimingKind.allDay,
  BridgeAgendaTimingKind.undated => AgendaTimingKind.undated,
};
AgendaTiming fromAgendaTiming(BridgeAgendaTiming v) => AgendaTiming(
  kind: fromAgendaTimingKind(v.kind),
  start: v.start == null ? null : fromAgendaTime(v.start!),
  end: v.end == null ? null : fromAgendaTime(v.end!),
  due: v.due == null ? null : fromAgendaTime(v.due!),
  from: v.from,
  to: v.to,
);
AgendaSubmission fromAgendaSubmission(BridgeAgendaSubmission v) => switch (v) {
  BridgeAgendaSubmission.submitted => AgendaSubmission.submitted,
  BridgeAgendaSubmission.partial => AgendaSubmission.partial,
  BridgeAgendaSubmission.unsubmitted => AgendaSubmission.unsubmitted,
  BridgeAgendaSubmission.unknown => AgendaSubmission.unknown,
};
AgendaUpstreamStatus fromAgendaUpstreamStatus(BridgeAgendaUpstreamStatus v) =>
    AgendaUpstreamStatus(
      feature: fromAgendaFeature(v.feature),
      completed: v.completed,
      beginTime: v.beginTime,
      endTime: v.endTime,
      examStatus: v.examStatus,
      checkin: v.checkin,
      pass: v.pass,
      submission: v.submission == null
          ? null
          : fromAgendaSubmission(v.submission!),
      text: v.text,
      orderStatus: v.orderStatus,
      checkStatus: v.checkStatus,
      signStatus: v.signStatus,
      weekCount: v.weekCount,
      termCount: v.termCount,
    );
AgendaNavigation fromAgendaNavigation(BridgeAgendaNavigation v) =>
    AgendaNavigation(
      feature: fromAgendaFeature(v.feature),
      term: v.term,
      week: v.week,
      courseCode: v.courseCode,
      serial: v.serial,
      day: v.day,
      section: v.section,
      courseId: v.courseId,
      bykcCourseId: v.bykcCourseId?.toInt(),
      assignmentId: v.assignmentId,
      orderId: v.orderId,
      taskId: v.taskId,
      courseNo: v.courseNo,
      courseName: v.courseName,
      date: v.date,
      startTime: v.startTime,
    );
SchoolAgendaItem fromSchoolAgendaItem(BridgeSchoolAgendaItem v) =>
    SchoolAgendaItem(
      key: fromSchoolAgendaKey(v.key),
      timing: fromAgendaTiming(v.timing),
      sortTime: v.sortTime == null ? null : fromAgendaTime(v.sortTime!),
      title: v.title,
      subtitle: v.subtitle,
      location: v.location,
      statusLabel: v.statusLabel,
      upstreamStatus: fromAgendaUpstreamStatus(v.upstreamStatus),
      navigation: fromAgendaNavigation(v.navigation),
      homeTodo: v.homeTodo,
    );
AgendaEntry fromAgendaEntry(BridgeAgendaEntry v) => AgendaEntry(
  local: v.local == null ? null : fromAgendaOccurrence(v.local!),
  school: v.school == null ? null : fromSchoolAgendaItem(v.school!),
  timing: fromAgendaTiming(v.timing),
  sortTime: v.sortTime == null ? null : fromAgendaTime(v.sortTime!),
  soon: v.soon,
  completed: v.completed,
  hidden: v.hidden,
  note: v.note,
);
AgendaCacheKind fromAgendaCacheKind(BridgeAgendaCacheKind v) => switch (v) {
  BridgeAgendaCacheKind.bykcChosen => AgendaCacheKind.bykcChosen,
  BridgeAgendaCacheKind.spocSelection => AgendaCacheKind.spocSelection,
  BridgeAgendaCacheKind.spocTerm => AgendaCacheKind.spocTerm,
  BridgeAgendaCacheKind.judgeSummaries => AgendaCacheKind.judgeSummaries,
  BridgeAgendaCacheKind.cgyyOrders => AgendaCacheKind.cgyyOrders,
  BridgeAgendaCacheKind.signinToday => AgendaCacheKind.signinToday,
  BridgeAgendaCacheKind.exams => AgendaCacheKind.exams,
  BridgeAgendaCacheKind.ygdkOverviewSelection =>
    AgendaCacheKind.ygdkOverviewSelection,
  BridgeAgendaCacheKind.ygdkOverviewPeriod =>
    AgendaCacheKind.ygdkOverviewPeriod,
  BridgeAgendaCacheKind.scheduleWeeks => AgendaCacheKind.scheduleWeeks,
  BridgeAgendaCacheKind.scheduleWeek => AgendaCacheKind.scheduleWeek,
  BridgeAgendaCacheKind.importedSchedules => AgendaCacheKind.importedSchedules,
  BridgeAgendaCacheKind.unknown => AgendaCacheKind.unknown,
};
AgendaCacheScope fromAgendaCacheScope(BridgeAgendaCacheScope v) =>
    AgendaCacheScope(
      route: fromConnectionMode(v.route),
      kind: fromAgendaCacheKind(v.kind),
      term: v.term,
      week: v.week,
      date: v.date,
      page: v.page,
      size: v.size,
      includeExpired: v.includeExpired,
      classifyId: v.classifyId,
      termId: v.termId,
      weekStart: v.weekStart,
    );
AgendaCompleteness fromAgendaCompleteness(BridgeAgendaCompleteness v) =>
    switch (v) {
      BridgeAgendaCompleteness.complete => AgendaCompleteness.complete,
      BridgeAgendaCompleteness.partial => AgendaCompleteness.partial,
    };
AgendaObservation fromAgendaObservation(BridgeAgendaObservation v) =>
    AgendaObservation(
      scope: fromAgendaCacheScope(v.scope),
      fetchedAt: v.fetchedAt.toInt(),
      lastVerifiedAt: v.lastVerifiedAt.toInt(),
      lastAttemptAt: v.lastAttemptAt.toInt(),
      lastAttemptSucceeded: v.lastAttemptSucceeded,
      completeness: fromAgendaCompleteness(v.completeness),
    );
AgendaSource fromAgendaSource(BridgeAgendaSource v) => AgendaSource(
  feature: fromAgendaFeature(v.feature),
  observations: v.observations.map((v) => fromAgendaObservation(v)).toList(),
  missingScopes: v.missingScopes.map((v) => fromAgendaCacheScope(v)).toList(),
  semesterImported: v.semesterImported,
  unprojectableCount: v.unprojectableCount,
);
BridgeAgendaQuery toAgendaQuery(AgendaQuery v) => BridgeAgendaQuery(
  route: toConnectionMode(v.route),
  term: v.term,
  from: v.from,
  to: v.to,
  now: toAgendaTime(v.now),
  includeHidden: v.includeHidden,
  ygdkEnabled: v.ygdkEnabled,
  ygdkWeekDone: v.ygdkWeekDone,
  ygdkTermDone: v.ygdkTermDone,
);
AgendaQueryResult fromAgendaQueryResult(BridgeAgendaQueryResult v) =>
    AgendaQueryResult(
      entries: v.entries.map((v) => fromAgendaEntry(v)).toList(),
      sources: v.sources.map((v) => fromAgendaSource(v)).toList(),
      schoolCacheFailure: v.schoolCacheFailure == null
          ? null
          : fromCacheFailure(v.schoolCacheFailure!),
    );

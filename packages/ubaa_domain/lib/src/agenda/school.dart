/// 本机日程的不可变领域值，不携带学校操作资格。
library;

import '../common/route.dart';
import '../common/cache_management.dart';
import 'models.dart';

enum AgendaFeature { bykc, spoc, judge, cgyy, signin, exam, ygdk, schedule }

enum AgendaTimingKind { period, deadline, allDay, undated }

final class AgendaTiming {
  AgendaTiming({
    required this.kind,
    this.start,
    this.end,
    this.due,
    this.from,
    this.to,
  });
  final AgendaTimingKind kind;
  final AgendaTime? start;
  final AgendaTime? end;
  final AgendaTime? due;
  final String? from;
  final String? to;
}

enum AgendaSubmission { submitted, partial, unsubmitted, unknown }

final class AgendaUpstreamStatus {
  AgendaUpstreamStatus({
    required this.feature,
    required this.completed,
    this.beginTime,
    this.endTime,
    this.examStatus,
    this.checkin,
    this.pass,
    this.submission,
    this.text,
    this.orderStatus,
    this.checkStatus,
    this.signStatus,
    this.weekCount,
    this.termCount,
  });
  final AgendaFeature feature;
  final bool completed;
  final String? beginTime;
  final String? endTime;
  final int? examStatus;
  final int? checkin;
  final int? pass;
  final AgendaSubmission? submission;
  final String? text;
  final int? orderStatus;
  final int? checkStatus;
  final int? signStatus;
  final int? weekCount;
  final int? termCount;
}

final class AgendaNavigation {
  AgendaNavigation({
    required this.feature,
    this.term,
    this.week,
    this.courseCode,
    this.serial,
    this.day,
    this.section,
    this.courseId,
    this.bykcCourseId,
    this.assignmentId,
    this.orderId,
    this.taskId,
    this.courseNo,
    this.courseName,
    this.date,
    this.startTime,
  });
  final AgendaFeature feature;
  final String? term;
  final int? week;
  final String? courseCode;
  final String? serial;
  final int? day;
  final int? section;
  final String? courseId;
  final int? bykcCourseId;
  final String? assignmentId;
  final int? orderId;
  final String? taskId;
  final String? courseNo;
  final String? courseName;
  final String? date;
  final String? startTime;
}

final class SchoolAgendaItem {
  SchoolAgendaItem({
    required this.key,
    required this.timing,
    this.sortTime,
    required this.title,
    required this.subtitle,
    this.location,
    required this.statusLabel,
    required this.upstreamStatus,
    required this.navigation,
    required this.homeTodo,
  });
  final SchoolAgendaKey key;
  final AgendaTiming timing;
  final AgendaTime? sortTime;
  final String title;
  final String subtitle;
  final String? location;
  final String statusLabel;
  final AgendaUpstreamStatus upstreamStatus;
  final AgendaNavigation navigation;
  final bool homeTodo;
}

final class AgendaEntry {
  AgendaEntry({
    this.local,
    this.school,
    required this.timing,
    this.sortTime,
    required this.soon,
    required this.completed,
    required this.hidden,
    this.note,
  });
  final AgendaOccurrence? local;
  final SchoolAgendaItem? school;
  final AgendaTiming timing;
  final AgendaTime? sortTime;
  final bool soon;
  final bool completed;
  final bool hidden;
  final String? note;
}

enum AgendaCacheKind {
  bykcChosen,
  spocSelection,
  spocTerm,
  judgeSummaries,
  cgyyOrders,
  signinToday,
  exams,
  ygdkOverviewSelection,
  ygdkOverviewPeriod,
  scheduleWeeks,
  scheduleWeek,
  importedSchedules,
  unknown,
}

final class AgendaCacheScope {
  AgendaCacheScope({
    required this.route,
    required this.kind,
    this.term,
    this.week,
    this.date,
    this.page,
    this.size,
    this.includeExpired,
    this.classifyId,
    this.termId,
    this.weekStart,
  });
  final ConnectionMode route;
  final AgendaCacheKind kind;
  final String? term;
  final int? week;
  final String? date;
  final int? page;
  final int? size;
  final bool? includeExpired;
  final int? classifyId;
  final int? termId;
  final String? weekStart;
}

enum AgendaCompleteness { complete, partial }

final class AgendaObservation {
  AgendaObservation({
    required this.scope,
    required this.fetchedAt,
    required this.lastVerifiedAt,
    required this.lastAttemptAt,
    required this.lastAttemptSucceeded,
    required this.completeness,
  });
  final AgendaCacheScope scope;
  final int fetchedAt;
  final int lastVerifiedAt;
  final int lastAttemptAt;
  final bool lastAttemptSucceeded;
  final AgendaCompleteness completeness;
}

final class AgendaSource {
  AgendaSource({
    required this.feature,
    required List<AgendaObservation> observations,
    required List<AgendaCacheScope> missingScopes,
    this.semesterImported,
    required this.unprojectableCount,
  }) : observations = List.unmodifiable(observations),
       missingScopes = List.unmodifiable(missingScopes);
  final AgendaFeature feature;
  final List<AgendaObservation> observations;
  final List<AgendaCacheScope> missingScopes;
  final bool? semesterImported;
  final int unprojectableCount;
}

final class AgendaQuery {
  AgendaQuery({
    required this.route,
    required this.term,
    required this.from,
    required this.to,
    required this.now,
    required this.includeHidden,
    required this.ygdkEnabled,
    required this.ygdkWeekDone,
    required this.ygdkTermDone,
  });
  final ConnectionMode route;
  final String term;
  final String from;
  final String to;
  final AgendaTime now;
  final bool includeHidden;
  final bool ygdkEnabled;
  final bool ygdkWeekDone;
  final bool ygdkTermDone;
}

final class AgendaQueryResult {
  AgendaQueryResult({
    required List<AgendaEntry> entries,
    required List<AgendaSource> sources,
    this.schoolCacheFailure,
  }) : entries = List.unmodifiable(entries),
       sources = List.unmodifiable(sources);
  final List<AgendaEntry> entries;
  final List<AgendaSource> sources;
  final CacheMaintenanceFailure? schoolCacheFailure;
}

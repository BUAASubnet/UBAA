import '../common/route.dart';
import '../feature/query.dart';
import '../feature/read_navigation.dart';
import '../feature/catalog.dart';
import 'models.dart';
import 'school.dart';

DateTime campusDate(DateTime value) =>
    value.toUtc().add(const Duration(hours: 8));
String agendaDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
const agendaWeekdays = ['一', '二', '三', '四', '五', '六', '日'];

AgendaTime agendaTime(DateTime value) => AgendaTime(
  rfc3339:
      '${agendaDate(value)}T${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:00+08:00',
  timezone: 'Asia/Shanghai',
);
DateTime? agendaValue(AgendaTime? value) =>
    value == null ? null : campusDate(DateTime.parse(value.rfc3339));

/// 日历几何使用北京时间的年月日字段，领域时间仍由 Core 提供。
DateTime agendaDay(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
DateTime? agendaStart(AgendaEntry entry) => entry.timing.from != null
    ? DateTime.tryParse('${entry.timing.from}T00:00:00Z')
    : agendaValue(entry.timing.start);
DateTime? agendaEnd(AgendaEntry entry) => entry.timing.to != null
    ? DateTime.tryParse('${entry.timing.to}T00:00:00Z')
    : agendaValue(entry.timing.end);

/// 同一天同名同地点的课程，若前一节结束到后一节开始不超过 20 分钟，界面合并为一段显示。
bool agendaCourseContinues(
  AgendaEntry a,
  DateTime aEnd,
  AgendaEntry b,
  DateTime bStart,
) {
  if (a.school?.navigation.feature != AgendaFeature.schedule ||
      b.school?.navigation.feature != AgendaFeature.schedule) {
    return false;
  }
  if (a.school!.title != b.school!.title ||
      (a.school!.location ?? '') != (b.school!.location ?? '')) {
    return false;
  }
  final gap = bStart.difference(aEnd);
  return !gap.isNegative &&
      gap <= const Duration(minutes: 20) &&
      agendaDay(aEnd) == agendaDay(bStart);
}

/// 将已按开始时间排序的条目中连续课程合并，返回（条目，显示结束时间）。
/// 中间夹有签到等其他条目时同样合并。
List<(AgendaEntry, DateTime?)> agendaMergeCourses(List<AgendaEntry> sorted) {
  final out = <(AgendaEntry, DateTime?)>[];
  outer:
  for (final e in sorted) {
    final start = agendaStart(e);
    if (start != null &&
        e.school?.navigation.feature == AgendaFeature.schedule) {
      for (var k = out.length - 1; k >= 0; k--) {
        final (prev, prevEnd) = out[k];
        if (prevEnd != null && agendaCourseContinues(prev, prevEnd, e, start)) {
          out[k] = (prev, agendaEnd(e) ?? prevEnd);
          continue outer;
        }
      }
    }
    out.add((e, agendaEnd(e)));
  }
  return out;
}

FeatureReadNavigation agendaNavigation(AgendaNavigation n) {
  final feature = FeatureId.values.byName(n.feature.name);
  final query = switch (n.feature) {
    AgendaFeature.schedule => FeatureQuery(
      view: FeatureQueryView.summary,
      term: n.term,
      week: n.week,
    ),
    AgendaFeature.bykc when n.bykcCourseId == null => const FeatureQuery(
      view: FeatureQueryView.bykcChosenCourses,
    ),
    AgendaFeature.bykc => FeatureQuery(
      view: FeatureQueryView.bykcDetail,
      courseId: '${n.bykcCourseId}',
    ),
    AgendaFeature.spoc => FeatureQuery(
      view: FeatureQueryView.spocDetail,
      assignmentId: n.assignmentId,
    ),
    AgendaFeature.judge => FeatureQuery(
      view: FeatureQueryView.judgeDetail,
      courseId: n.courseId,
      assignmentId: n.assignmentId,
    ),
    AgendaFeature.exam => FeatureQuery(
      view: FeatureQueryView.examArranged,
      term: n.term?.isEmpty == true ? null : n.term,
    ),
    AgendaFeature.signin => const FeatureQuery(
      view: FeatureQueryView.signinPending,
    ),
    AgendaFeature.cgyy => const FeatureQuery(view: FeatureQueryView.cgyyOrders),
    _ => const FeatureQuery(),
  };
  return FeatureReadNavigation(feature: feature, query: query);
}

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

/// 最近一次成功向学校确认的时间：内容未变化时核验时间不前进，但确认已完成。
int agendaCheckedAt(Iterable<AgendaObservation> observations) => observations
    .map(
      (o) => o.lastAttemptSucceeded && o.lastAttemptAt > o.lastVerifiedAt
          ? o.lastAttemptAt
          : o.lastVerifiedAt,
    )
    .reduce((a, b) => a > b ? a : b);

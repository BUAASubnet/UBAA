import 'dart:convert';
import '../feature/presentation.dart';
import '../feature/schedule/widget_snapshot.dart';
import 'presentation.dart';
import 'school.dart';
import 'widget_links.dart';

part 'widget_items.dart';
part 'widget_cards.dart';
part 'widget_todo.dart';

typedef _Row = Map<String, Object?>;
const _day = 86400;
int _stamp(DateTime campus) =>
    campus.toUtc().millisecondsSinceEpoch ~/ 1000 - 28800;
DateTime _wall(int stamp) =>
    DateTime.fromMillisecondsSinceEpoch((stamp + 28800) * 1000, isUtc: true);
int _midnight(int stamp) => _stamp(agendaDay(_wall(stamp)));
String _hm(int stamp) {
  final time = _wall(stamp);
  return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
}

String _md(int date) => agendaDate(_wall(date)).substring(5);
String _relative(int date, int day) => switch ((date - day) ~/ _day) {
  0 => '',
  1 => '明天',
  >= 2 && <= 6 => '周${agendaWeekdays[_wall(date).weekday - 1]}',
  _ => _md(date),
};
String? _display(String? value) =>
    value == null ? null : String.fromCharCodes(value.runes.take(64));

class _Segments {
  List<_Row>? rows = [];
  String? previous;
  void add(int from, _Row Function() state) {
    if (rows == null) return;
    final value = state();
    final encoded = jsonEncode(value);
    if (previous == encoded) return;
    previous = encoded;
    if (rows!.length == 2000) {
      rows = null;
      return;
    }
    rows!.add({'from': from, ...value});
  }
}

class _Coverage {
  _Coverage(String term, List<WeekPresentation> weeks, AgendaQueryResult data) {
    if (term.isEmpty) return;
    final verified = <int>{}, missing = <int>{};
    indexMissing = data.schoolCacheFailure != null;
    for (final source in data.sources.where(
      (source) => source.feature == AgendaFeature.schedule,
    )) {
      for (final scope in source.missingScopes) {
        if (scope.kind == AgendaCacheKind.scheduleWeeks) indexMissing = true;
        if (scope.kind == AgendaCacheKind.scheduleWeek &&
            scope.term == term &&
            scope.week != null)
          missing.add(scope.week!);
      }
      for (final obs in source.observations) {
        final scope = obs.scope;
        if (obs.lastAttemptSucceeded &&
            obs.completeness == AgendaCompleteness.complete &&
            scope.kind == AgendaCacheKind.scheduleWeek &&
            scope.term == term &&
            scope.week != null)
          verified.add(scope.week!);
      }
    }
    for (final week in weeks) {
      final start = widgetWeekDate(week.startDate),
          end = widgetWeekDate(week.endDate);
      if (week.responseTerm != term ||
          week.requestTerm != term ||
          week.number < 1 ||
          start == null ||
          end == null ||
          end.isBefore(start) ||
          end.difference(start).inDays > 6)
        continue;
      final from = _stamp(start), to = _stamp(end);
      if (first == null || from < first!) first = from;
      if (last == null || to > last!) last = to;
      for (var date = from; date <= to; date += _day) {
        days[date] =
            !days.containsKey(date) &&
            !indexMissing &&
            verified.contains(week.number) &&
            !missing.contains(week.number);
      }
    }
  }
  int? first, last;
  bool indexMissing = false;
  final days = <int, bool>{};
  bool through(int day, int target) {
    if (first == null || indexMissing) return false;
    for (var date = day; date <= target && date <= last!; date += _day) {
      if (date >= first! && days[date] != true) return false;
    }
    return true;
  }

  String empty(int day) {
    if (!through(day, day + 13 * _day)) return 'partial';
    return last! < day + 13 * _day ? 'termEnd' : 'none';
  }
}

DateTime? widgetWeekDate(String raw) {
  final key = raw.trim().split(RegExp('[ T]')).first;
  final date = DateTime.tryParse('${key}T00:00:00Z');
  return date != null && agendaDate(date) == key ? date : null;
}

ScheduleWidgetSnapshot buildWidgetSnapshot({
  required String owner,
  required List<Map<String, Object?>> semesters,
  required DateTime now,
  required String term,
  required List<WeekPresentation> weeks,
  required AgendaQueryResult? agenda,
}) {
  final start = widgetDayStart(now), end = start + 14 * _day;
  if (agenda == null)
    return ScheduleWidgetSnapshot(
      owner: owner,
      semesters: semesters,
      dayStart: start,
    );
  final items = _items(owner, agenda.entries);
  final periods = items.where((item) => item.start != null).toList();
  final exams = items.where((item) => item.kind == 'exam').toList();
  final deadlines = items.where((item) => item.due != null).toList();
  final todayItems = items.where((item) => item.due == null).toList()
    ..sort((a, b) {
      final day = a.day.compareTo(b.day);
      if (day != 0) return day;
      if ((a.start == null) != (b.start == null))
        return a.start == null ? -1 : 1;
      return _order(a, b);
    });
  final observations = agenda.sources
      .where(
        (s) => {
          AgendaFeature.exam,
          AgendaFeature.judge,
          AgendaFeature.spoc,
          AgendaFeature.ygdk,
        }.contains(s.feature),
      )
      .expand((s) => s.observations);
  final checked = observations.isEmpty ? null : agendaCheckedAt(observations);
  final boundaries = <int>{
    for (var day = start; day < end; day += _day) day,
    if (checked != null) checked + _day,
    for (final item in items) ...[
      if (item.start != null) ...[item.start!, item.start! - 3600],
      if (item.end != null) item.end!,
      if (item.due != null) item.due!,
    ],
  }.where((t) => t >= start && t < end).toList()..sort();
  final coverage = _Coverage(term, weeks, agenda),
      home = widgetLink(owner, 'home'),
      todoLink = widgetLink(owner, 'agendaTodo');
  final up = _Segments(), today = _Segments(), todo = _Segments();
  for (final at in boundaries) {
    final day = _midnight(at);
    up.add(at, () => _upNext(periods, exams, at, day, coverage, home));
    today.add(
      at,
      () => _today(todayItems, deadlines, at, day, coverage, owner, home),
    );
    todo.add(at, () => _todo(exams, deadlines, at, day, checked, todoLink));
  }
  return ScheduleWidgetSnapshot(
    owner: owner,
    semesters: semesters,
    dayStart: start,
    upNext: up.rows,
    today: today.rows,
    todo: todo.rows,
  );
}

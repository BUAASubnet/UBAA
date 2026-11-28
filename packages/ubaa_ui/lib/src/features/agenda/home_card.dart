import 'package:ubaa_domain/ubaa_domain.dart';

import 'format.dart';
import 'home_card_model.dart';

export 'home_card_model.dart';

const _cardLimit = 12;

HomeCardSnapshot buildHomeCardSnapshot(
  List<AgendaEntry> entries, {
  required DateTime now,
  required bool signedIn,
}) {
  final today = agendaDate(now);
  final agenda = <AgendaEntry>[];
  final homework = <AgendaEntry>[];
  final todo = <AgendaEntry>[];
  for (final entry in signedIn ? entries : const <AgendaEntry>[]) {
    if (entry.completed || entry.hidden) continue;
    final timing = entry.timing;
    final feature = entry.school?.navigation.feature;
    if (entry.local == null &&
        (feature == AgendaFeature.spoc || feature == AgendaFeature.judge)) {
      homework.add(entry);
      continue;
    }
    if (timing.kind == AgendaTimingKind.period) {
      final start = timing.start?.rfc3339;
      if (start != null && start.startsWith(today)) agenda.add(entry);
      continue;
    }
    if (entry.local != null ||
        feature == AgendaFeature.bykc ||
        feature == AgendaFeature.signin ||
        feature == AgendaFeature.ygdk ||
        feature == AgendaFeature.cgyy) {
      todo.add(entry);
    }
  }
  int byStart(AgendaEntry a, AgendaEntry b) => (a.timing.start?.rfc3339 ?? '~')
      .compareTo(b.timing.start?.rfc3339 ?? '~');
  int byDue(AgendaEntry a, AgendaEntry b) =>
      (a.timing.due?.rfc3339 ?? a.timing.start?.rfc3339 ?? '~').compareTo(
        b.timing.due?.rfc3339 ?? b.timing.start?.rfc3339 ?? '~',
      );
  agenda.sort(byStart);
  homework.sort(byDue);
  todo.sort(byDue);
  final week = _week(now, signedIn ? entries : const <AgendaEntry>[]);
  return HomeCardSnapshot(
    campusDay: today,
    dateLabel: agendaMonthDayWeek(now),
    signedIn: signedIn,
    agenda: [for (final entry in agenda.take(_cardLimit)) _item(entry, now)],
    homework: [
      for (final entry in homework.take(_cardLimit))
        _item(entry, now, due: true),
    ],
    todo: [
      for (final entry in todo.take(_cardLimit)) _item(entry, now, due: true),
    ],
    weekLabel: week.label,
    todayWeekday: week.today,
    weekRows: week.rows,
  );
}

({String label, int today, List<HomeCardWeekRow> rows}) _week(
  DateTime now,
  List<AgendaEntry> entries,
) {
  final day = campusDate(now);
  final monday = DateTime.utc(day.year, day.month, day.day - (day.weekday - 1));
  final sunday = monday.add(const Duration(days: 6));
  final label = '${monday.month}.${monday.day}–${sunday.month}.${sunday.day}';
  final byStart = <String, Map<int, List<AgendaEntry>>>{};
  for (final entry in entries) {
    if (entry.completed || entry.hidden) continue;
    if (entry.timing.kind != AgendaTimingKind.period) continue;
    final start = entry.timing.start?.rfc3339;
    if (start == null || start.length < 16) continue;
    final date = start.substring(0, 10);
    if (date.compareTo(agendaDate(monday)) < 0 ||
        date.compareTo(agendaDate(sunday)) > 0) {
      continue;
    }
    final weekday = DateTime.tryParse(date)?.weekday;
    if (weekday == null) continue;
    final startAt = start.substring(11, 16);
    (byStart[startAt] ??= {}).putIfAbsent(weekday, () => []).add(entry);
  }
  final rows = <HomeCardWeekRow>[];
  for (final startAt in byStart.keys.toList()..sort()) {
    final cells = <HomeCardWeekCell>[];
    for (var weekday = 1; weekday <= 7; weekday++) {
      final items = byStart[startAt]![weekday] ?? const <AgendaEntry>[];
      if (items.isEmpty) {
        cells.add(const HomeCardWeekCell.empty());
        continue;
      }
      final titles = <String>[];
      String? location;
      for (final entry in items) {
        final title = agendaTitle(entry);
        if (!titles.contains(title)) titles.add(title);
        location ??= _homeCardLocation(entry);
      }
      final end = items.first.timing.end?.rfc3339;
      cells.add(
        HomeCardWeekCell(
          title: titles.join(' / '),
          time: end == null || end.length < 16 ? '' : end.substring(11, 16),
          location: location ?? '',
          color: _courseColor(titles.first),
        ),
      );
    }
    rows.add(HomeCardWeekRow(time: startAt, cells: cells));
  }
  return (
    label: label,
    today: day.weekday,
    rows: rows.take(16).toList(growable: false),
  );
}

int _courseColor(String title) {
  var hash = 0;
  for (final unit in title.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash % 8;
}

HomeCardItem _item(AgendaEntry entry, DateTime now, {bool due = false}) =>
    HomeCardItem(
      title: agendaTitle(entry),
      time: due ? homeCardDue(entry, now) : homeCardTime(entry.timing),
      location: _homeCardLocation(entry),
    );

String? _homeCardLocation(AgendaEntry entry) {
  final location = entry.local?.content.location ?? entry.school?.location;
  final trimmed = location?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String homeCardTime(AgendaTiming timing) {
  final start = timing.start?.rfc3339;
  if (start == null || start.length < 16) return '时间待定';
  final startHm = start.substring(11, 16);
  final end = timing.end?.rfc3339;
  if (end == null || end.length < 16) return startHm;
  return '$startHm–${end.substring(11, 16)}';
}

String homeCardDue(AgendaEntry entry, DateTime now) {
  final timing = entry.timing;
  final raw = timing.due?.rfc3339 ?? timing.start?.rfc3339;
  if (raw == null || raw.length < 10) return '无截止';
  final hm = raw.length >= 16 ? ' ${raw.substring(11, 16)}' : '';
  final today = agendaDate(now);
  final tomorrow = agendaDate(now.add(const Duration(days: 1)));
  final date = raw.substring(0, 10);
  if (date == today) return '今天$hm';
  if (date == tomorrow) return '明天$hm';
  final month = int.tryParse(raw.substring(5, 7));
  final day = int.tryParse(raw.substring(8, 10));
  if (month == null || day == null) return '待定';
  return '$month月$day日$hm';
}

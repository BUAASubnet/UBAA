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
  );
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

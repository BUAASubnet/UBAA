part of 'widget_tables.dart';

class _Item {
  _Item(
    this.entry,
    this.kind,
    this.day,
    this.start,
    this.end,
    this.due,
    this.link,
    this.key,
  );
  final AgendaEntry entry;
  final String kind, link, key;
  final int day;
  final int? start, end, due;
  int get orderAt => start ?? due ?? day;
  int get priority => const [
    'exam',
    'course',
    'bykc',
    'cgyy',
    'judge',
    'spoc',
    'ygdk',
    'local',
  ].indexOf(kind);
  bool get private => entry.local != null;
  String get title => entry.local?.content.title ?? entry.school!.title;
  String? get place {
    if (kind == 'exam') return entry.school!.subtitle;
    final value = entry.local?.content.location ?? entry.school?.location;
    return value == null || value.trim().isEmpty ? null : value;
  }

  String? get tag => switch (kind) {
    'exam' => '考试',
    'bykc' => '博雅',
    'cgyy' => '预约',
    _ => null,
  };
  bool live(int at) => at < (end ?? start ?? (day + _day));
  bool ongoing(int at) =>
      start != null && end != null && start! <= at && at < end!;
  String? get range =>
      start == null || end == null ? null : '${_hm(start!)}–${_hm(end!)}';
  _Row get identity => {
    'kind': kind,
    'tag': tag,
    'title': _display(title),
    'place': _display(place),
  };
}

int _order(_Item left, _Item right) {
  final time = left.orderAt.compareTo(right.orderAt);
  if (time != 0) return time;
  final priority = left.priority.compareTo(right.priority);
  return priority != 0 ? priority : left.key.compareTo(right.key);
}

List<_Item> _items(String owner, List<AgendaEntry> entries) {
  final visible =
      entries
          .where(
            (e) =>
                !e.hidden &&
                !e.completed &&
                e.school?.navigation.feature != AgendaFeature.signin,
          )
          .toList()
        ..sort(
          (a, b) => (agendaStart(a)?.millisecondsSinceEpoch ?? 0).compareTo(
            agendaStart(b)?.millisecondsSinceEpoch ?? 0,
          ),
        );
  final result = <_Item>[];
  for (final (entry, mergedEnd) in agendaMergeCourses(visible)) {
    final school = entry.school,
        local = entry.local,
        feature = school?.navigation.feature;
    if (local == null &&
        (school == null ||
            feature != AgendaFeature.schedule && !school.homeTodo))
      continue;
    final timing = entry.timing;
    final kind = feature == AgendaFeature.schedule
        ? 'course'
        : feature?.name ?? 'local';
    int? start, end, due;
    DateTime? date;
    if (timing.kind == AgendaTimingKind.deadline &&
        {'judge', 'spoc', 'ygdk', 'local'}.contains(kind)) {
      date = agendaValue(timing.due);
      if (date == null) continue;
      due = _stamp(date);
    } else if (timing.kind == AgendaTimingKind.period &&
        {'course', 'exam', 'bykc', 'cgyy', 'local'}.contains(kind)) {
      date = agendaValue(timing.start);
      if (date != null) start = _stamp(date);
      if (mergedEnd != null) end = _stamp(mergedEnd);
      if (date == null) {
        if (kind != 'exam' || end == null) continue;
        date = widgetWeekDate(school?.navigation.date ?? '') ?? mergedEnd;
      }
    } else if (kind == 'exam' && timing.kind == AgendaTimingKind.allDay) {
      date = widgetWeekDate(timing.from ?? '');
    } else {
      continue;
    }
    if (date == null) continue;
    final day = _stamp(agendaDay(date));
    final link = local != null || kind == 'course'
        ? widgetLink(
            owner,
            local == null ? 'schedule' : 'agenda',
            date: agendaDate(date),
          )
        : widgetLink(
            owner,
            'feature',
            navigation: agendaNavigation(school!.navigation),
          );
    result.add(
      _Item(
        entry,
        kind,
        day,
        start,
        end,
        due,
        link,
        local == null
            ? school!.key.upstreamId
            : '${local.itemId}:${local.recurrenceId}',
      ),
    );
  }
  return result..sort(_order);
}

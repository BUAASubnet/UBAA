part of 'widget_tables.dart';

String? _message(String state) => switch (state) {
  'partial' => '部分课表未载入',
  'termEnd' => '本学期课程已结束',
  'none' => '近期没有安排',
  _ => null,
};

_Row _upNext(
  List<_Item> periods,
  List<_Item> exams,
  int at,
  int day,
  _Coverage cover,
  String home,
) {
  _Item? primary;
  for (final item in periods.where((item) => item.ongoing(at))) {
    if (primary == null || item.priority < primary.priority) primary = item;
  }
  final ongoing = primary != null;
  primary ??= periods.where((item) => item.start! > at).firstOrNull;
  final state = primary == null
      ? cover.empty(day)
      : ongoing || cover.through(day, primary.day)
      ? 'item'
      : 'partial';
  if (state != 'item') primary = null;
  _Row? line, second;
  if (primary != null) {
    final item = primary, start = item.start!;
    final prefix = ongoing ? '' : _relative(item.day, day);
    line = {
      ...item.identity,
      'timeText': ongoing
          ? item.range
          : [if (prefix.isNotEmpty) prefix, _hm(start)].join(' '),
      'dayText': prefix,
      'startText': _hm(start),
      'endText': item.end == null ? null : _hm(item.end!),
      'startAt': start,
      'endAt': item.end,
      'ongoing': ongoing,
      'countdown': ongoing
          ? {'label': '还剩', 'target': item.end}
          : start - at <= 3600
          ? {'label': '还有', 'target': start}
          : null,
      'extraCount': periods
          .where(
            (other) =>
                other.start == start &&
                !identical(other, item) &&
                other.live(at),
          )
          .length,
      'private': item.private,
      'link': item.link,
    };
  }
  final exam = exams
      .where((item) => item != primary && item.day == day && item.live(at))
      .firstOrNull;
  if (exam != null) {
    second = {
      'kind': 'exam',
      'text': _display(
        '${exam.start == null ? '今天有考试 · 时间待定' : '${_hm(exam.start!)} 考试'} · ${exam.place}',
      ),
      'private': false,
      'link': exam.link,
    };
  } else if (ongoing) {
    final next = periods
        .where((item) => item.day == day && item.start! > at)
        .firstOrNull;
    if (next != null)
      second = {
        'kind': 'next',
        'text': _display(
          '下一节 ${_hm(next.start!)}${next.place == null ? '' : ' ${next.place}'}',
        ),
        'private': next.private,
        'link': next.link,
      };
  }
  return {
    'state': state,
    'message': _message(state),
    'primary': line,
    'secondary': second,
    'cardLink': primary?.link ?? home,
  };
}

_Row _today(
  List<_Item> items,
  List<_Item> due,
  int at,
  int day,
  _Coverage cover,
  String owner,
  String home,
) {
  final remaining = items.where((item) => item.day >= day && item.live(at));
  final chosen = remaining.firstOrNull?.day;
  final state = chosen == null
      ? cover.empty(day)
      : cover.through(day, chosen)
      ? 'items'
      : 'partial';
  final listed = state == 'items';
  final count = listed && chosen == day
      ? due.where((item) => item.day == day && item.due! > at).length
      : 0;
  return {
    'state': state,
    'message': _message(state),
    'dayLabel': !listed
        ? null
        : chosen == day
        ? '今天'
        : _relative(chosen!, day),
    'rows': [
      if (listed)
        for (final item
            in remaining.takeWhile((item) => item.day == chosen).take(8))
          {
            ...item.identity,
            'timeText': item.start == null ? '待定' : _hm(item.start!),
            'endText': item.end == null ? null : _hm(item.end!),
            'rangeText': item.range,
            'ongoing': item.ongoing(at),
            'private': item.private,
            'link': item.link,
          },
    ],
    'dueLine': count == 0 ? null : '今天 $count 项截止',
    'cardLink': listed
        ? widgetLink(owner, 'schedule', date: agendaDate(_wall(chosen!)))
        : home,
  };
}

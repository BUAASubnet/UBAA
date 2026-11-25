part of 'widget_tables.dart';

_Row _todo(
  List<_Item> exams,
  List<_Item> deadlines,
  int at,
  int day,
  int? checked,
  String link,
) {
  final due = deadlines
      .where((item) => item.due! > at && item.due! < day + 7 * _day)
      .toList();
  final active = exams.where(
    (item) => item.live(at) && item.day < day + 14 * _day,
  );
  final firstExam = active.firstOrNull;
  final small =
      active
          .where((item) => item.day == day || item.day == day + _day)
          .firstOrNull ??
      due.firstOrNull ??
      firstExam;
  final medium = [
    if (firstExam != null) firstExam,
    ...due.take(firstExam == null ? 3 : 2),
  ];
  final state = small != null
      ? 'items'
      : checked == null
      ? 'noData'
      : 'empty';
  String? footer(int count) => count > 0 ? '还有 $count 项' : null;
  return {
    'state': state,
    'message': switch (state) {
      'noData' => '打开 UBAA 载入待办',
      'empty' => '近期没有待办',
      _ => null,
    },
    'smallRow': small == null ? null : _todoRow(small, at, day),
    'smallFooter': footer(due.length - (small?.due != null ? 1 : 0)),
    'mediumRows': [for (final item in medium) _todoRow(item, at, day)],
    'mediumFooter': footer(
      due.length - medium.where((item) => item.due != null).length,
    ),
    'staleText': checked == null || at < checked + _day
        ? null
        : '截至 ${day - _midnight(checked) == _day ? '昨天' : _md(checked)} ${_hm(checked)}',
    'cardLink': link,
  };
}

_Row _todoRow(_Item item, int at, int day) {
  final exam = item.kind == 'exam', delta = (item.day - day) ~/ _day;
  final left = exam
      ? (item.ongoing(at)
            ? '进行中'
            : switch (delta) {
                0 => '今天',
                1 => '明天',
                _ => '还有 $delta 天',
              })
      : '${delta == 0 ? '今天' : _relative(item.day, day)} ${_hm(item.due!)}';
  final sub = exam
      ? '${_md(item.day)} ${item.start == null ? '时间待定' : _hm(item.start!)} · ${item.place}'
      : switch (item.kind) {
          'judge' =>
            item.entry.school?.upstreamStatus.submission ==
                    AgendaSubmission.partial
                ? '希冀作业 · 部分完成'
                : '希冀作业',
          'spoc' => 'SPOC 作业',
          'ygdk' => '阳光打卡',
          _ => '待办',
        };
  return {
    'kind': item.kind,
    'title': _display(item.title),
    'leftText': _display(left),
    'sub': _display(sub),
    'urgent': delta == 0 || exam && delta == 1,
    'private': item.private,
    'link': item.link,
  };
}

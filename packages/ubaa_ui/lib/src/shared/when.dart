import 'package:clock/clock.dart';
import 'package:ubaa_domain/ubaa_domain.dart' show homeCampusTime;

/// 当前校园墙上时间。
DateTime uiCampusNow() => homeCampusTime(clock.now());

final _dateTime = RegExp(
  r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?',
);
final _clockOnly = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$');

/// 解析上游的校园时间文本；只有“HH:mm”时按 [day] 当天处理。
DateTime? uiParseCampusTime(String? raw, {DateTime? day}) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  if (_dateTime.firstMatch(text) case final m?) {
    return DateTime(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
      int.parse(m[4] ?? '0'),
      int.parse(m[5] ?? '0'),
      int.parse(m[6] ?? '0'),
    );
  }
  if (_clockOnly.firstMatch(text) case final m?) {
    final base = day ?? uiCampusNow();
    return DateTime(
      base.year,
      base.month,
      base.day,
      int.parse(m[1]!),
      int.parse(m[2]!),
    );
  }
  return null;
}

bool _hasClock(String raw) => raw.contains(':');

String _two(int v) => v.toString().padLeft(2, '0');

String uiClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// “11月8日”；跨年时带年份。
String uiDay(DateTime t, {DateTime? now}) {
  final current = now ?? uiCampusNow();
  return t.year == current.year
      ? '${t.month}月${t.day}日'
      : '${t.year}年${t.month}月${t.day}日';
}

/// 去掉秒并改成“11月8日 23:59”；无法解析时原样返回。
String uiShortDateTime(String raw, {DateTime? now}) {
  final t = uiParseCampusTime(raw, day: now);
  if (t == null) return raw.trim();
  final day = _dateTime.hasMatch(raw.trim()) ? uiDay(t, now: now) : null;
  return [?day, if (_hasClock(raw)) uiClock(t)].join(' ');
}

/// 时间段：同一天只写一次日期，例如“11月7日 19:00–20:00”。
/// [withDate] 为 false 时只保留时刻（例如今天的签到列表）。
String? uiShortRange(
  String? start,
  String? end, {
  bool withDate = true,
  DateTime? now,
}) {
  final a = uiParseCampusTime(start, day: now);
  final b = uiParseCampusTime(end, day: now);
  if (a == null || b == null) {
    final s = start == null ? null : uiShortDateTime(start, now: now);
    final e = end == null ? null : uiShortDateTime(end, now: now);
    if ((s ?? '').isNotEmpty && (e ?? '').isNotEmpty) return '$s–$e';
    if ((s ?? '').isNotEmpty) return '$s 开始';
    if ((e ?? '').isNotEmpty) return '$e 结束';
    return null;
  }
  final sameDay = a.year == b.year && a.month == b.month && a.day == b.day;
  final datePart = withDate && _dateTime.hasMatch(start!.trim())
      ? '${uiDay(a, now: now)} '
      : '';
  if (sameDay) return '$datePart${uiClock(a)}–${uiClock(b)}';
  return '${uiShortDateTime(start!, now: now)}–${uiShortDateTime(end!, now: now)}';
}

/// 截止提示：“已截止”“今天截止”“明天截止”“还有 N 天”。
String? uiDeadlineHint(DateTime deadline, {DateTime? now}) {
  final current = now ?? uiCampusNow();
  if (!deadline.isAfter(current)) return '已截止';
  final days = DateTime(
    deadline.year,
    deadline.month,
    deadline.day,
  ).difference(DateTime(current.year, current.month, current.day)).inDays;
  return switch (days) {
    0 => '今天截止',
    1 => '明天截止',
    _ => '还有 $days 天',
  };
}

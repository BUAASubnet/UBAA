import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/spoc_classroom/classroom_format.dart';

ClassroomSessionSummary _period(
  DateTime start, {
  int? week,
  String title = '',
}) {
  final startSecs = start.millisecondsSinceEpoch ~/ 1000;
  return ClassroomSessionSummary(
    subId: '$startSecs',
    title: title,
    week: week,
    startSecs: startSecs,
    endSecs: startSecs + 3600,
    room: '',
    lecturer: '',
    status: ClassroomStatus.replay,
  );
}

void main() {
  test('教学周从新到旧，同周节次从早到晚', () {
    final older = _period(DateTime(2026, 11, 16), week: 10);
    final earlier = _period(DateTime(2026, 11, 23, 8), week: 11);
    final later = _period(DateTime(2026, 11, 23, 10), week: 11);
    final input = [older, later, earlier];

    final groups = groupSessionsByWeek(input);

    expect(groups.map((group) => group.label), ['第 11 周', '第 10 周']);
    expect(groups.map((group) => group.sessions), [
      [earlier, later],
      [older],
    ]);
    expect(input, [older, later, earlier]);
  });

  test('无周次时以周一为自然周起点，能与教学周同时分组', () {
    final sunday = _period(DateTime(2026, 11, 22));
    final previousMonday = _period(DateTime(2026, 11, 16));
    final monday = _period(DateTime(2026, 11, 23));
    final teaching = _period(DateTime(2026, 11, 23, 8), week: 11);

    final groups = groupSessionsByWeek([
      sunday,
      monday,
      previousMonday,
      teaching,
    ]);

    expect(groups.map((group) => group.label), [
      '第 11 周',
      '11/23 起的一周',
      '11/16 起的一周',
    ]);
    expect(groups.map((group) => group.sessions), [
      [teaching],
      [monday],
      [previousMonday, sunday],
    ]);
  });

  test('节次标签提取标题末尾的节次，其他标题保留原义', () {
    final start = DateTime(2026, 11, 23);
    for (final (title, label) in [
      ('周一 第8,9节  ', '第8,9节'),
      ('周一 第8-10节', '第8-10节'),
      ('第8、9节补课', '第8、9节补课'),
      (' 课堂答疑 ', '课堂答疑'),
      ('  ', '课堂'),
    ]) {
      expect(sessionPeriodLabel(_period(start, title: title)), label);
    }
  });

  test('媒体时钟处理负值、零、分钟与小时进位', () {
    for (final (duration, label) in const [
      (Duration(seconds: -8), '00:00'),
      (Duration.zero, '00:00'),
      (Duration(milliseconds: 65999), '01:05'),
      (Duration(minutes: 59, seconds: 59), '59:59'),
      (Duration(hours: 1), '1:00:00'),
      (Duration(hours: 12, minutes: 3, seconds: 4), '12:03:04'),
    ]) {
      expect(mediaClock(duration), label);
    }
  });
}

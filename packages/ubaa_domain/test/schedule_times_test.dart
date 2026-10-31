import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('校历14节不受本科课程、GSMIS方案、空周及时间冲突影响', () {
    const expected = [
      ('08:00', '08:45'),
      ('08:50', '09:35'),
      ('09:50', '10:35'),
      ('10:40', '11:25'),
      ('11:30', '12:15'),
      ('14:00', '14:45'),
      ('14:50', '15:35'),
      ('15:50', '16:35'),
      ('16:40', '17:25'),
      ('17:30', '18:15'),
      ('19:00', '19:45'),
      ('19:50', '20:35'),
      ('20:40', '21:25'),
      ('21:30', '22:15'),
    ];
    for (final courses in [
      <ScheduleCoursePresentation>[],
      [_course('09:00', '09:40')],
      [_course('09:00', '09:40'), _course('08:10', '09:30')],
    ]) {
      for (final explicit in [
        <ScheduleSectionTime>[],
        [
          const ScheduleSectionTime(1, '09:00', '09:45'),
          const ScheduleSectionTime(1, '08:10', '08:55'),
          const ScheduleSectionTime(14, '22:00', '22:45'),
        ],
      ]) {
        final times = scheduleSectionTimes(
          courses: courses,
          explicit: explicit,
        );
        expect(times.map((t) => (t.start, t.end)), expected);
        expect(times.map((t) => t.section), List.generate(14, (i) => i + 1));
      }
    }
  });
  test('校历以外节次保留接口优先、课程边界后备、冲突和缺失为空', () {
    final times = scheduleSectionTimes(
      courses: [
        _course('22:30', '23:15', begin: 15, end: 15),
        _course('23:20', '23:40', begin: 16, end: 16),
        _course('23:25', '23:40', begin: 16, end: 16),
        _course('23:45', '23:59', begin: 18, end: 18),
      ],
      explicit: const [ScheduleSectionTime(15, '22:20', '23:05')],
    );
    expect(times.length, 18);
    expect((times[14].start, times[14].end), ('22:20', '23:05'));
    expect((times[15].start, times[15].end), (null, '23:40'));
    expect((times[16].start, times[16].end), (null, null));
    expect((times[17].start, times[17].end), ('23:45', '23:59'));
    final conflict = scheduleSectionTimes(
      courses: [_course('22:30', '23:15', begin: 15, end: 15)],
      explicit: const [
        ScheduleSectionTime(15, '22:20', '23:05'),
        ScheduleSectionTime(15, '22:25', '23:05'),
      ],
    );
    expect((conflict.last.start, conflict.last.end), (null, '23:05'));
  });
}

ScheduleCoursePresentation _course(
  String start,
  String endTime, {
  int begin = 1,
  int end = 2,
}) => ScheduleCoursePresentation(
  courseCode: '合成课程',
  beginSection: begin,
  endSection: end,
  beginTime: start,
  endTime: endTime,
);

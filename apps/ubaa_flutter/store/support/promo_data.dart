// 宣传截图专用的虚构数据：人物、学号、课程安排与成绩均为编造，
// 只沿用校园公开的教学楼称呼与节次时间，不取自任何真实账号或夹具。

import 'package:ubaa_domain/ubaa_domain.dart';

/// 截图统一停在第 3 教学周的周二上午。
final storeNow = DateTime.parse('2026-09-22T09:41:00+08:00');
const storeTerm = '2026-2027-1';
const storeWeek = 3;
const storeWeekCount = 16;

/// 第 1 教学周的周一；周次与日期都由它推算。
final storeTermStart = DateTime.utc(2026, 9, 7);

const storeUsername = 'demo-ubaa';
const storeDisplayName = '林知远';

/// 节次时间沿用应用使用的公开作息。
final storeSections = scheduleSectionTimes(courses: const []);

final class StoreCourse {
  const StoreCourse({
    required this.code,
    required this.name,
    required this.day,
    required this.begin,
    required this.end,
    required this.place,
    required this.teacher,
    required this.color,
    this.credit = '3.0',
    this.firstWeek = 1,
    this.lastWeek = storeWeekCount,
  });

  final String code, name, place, teacher, color, credit;
  final int day, begin, end, firstWeek, lastWeek;

  String get beginTime => storeSections[begin - 1].start!;
  String get endTime => storeSections[end - 1].end!;
  String get time => '$beginTime-$endTime';
  String get weeksAndTeachers => '$firstWeek-$lastWeek周 · $teacher';

  bool occursIn(int week) => week >= firstWeek && week <= lastWeek;
}

const storeCourses = <StoreCourse>[
  StoreCourse(
    code: 'CS2101',
    name: '计算机组成原理',
    day: 1,
    begin: 1,
    end: 2,
    place: '主M201',
    teacher: '周老师',
    color: '#476FBD',
    credit: '4.0',
  ),
  StoreCourse(
    code: 'MA2103',
    name: '离散数学',
    day: 1,
    begin: 6,
    end: 7,
    place: '主M305',
    teacher: '许老师',
    color: '#7B5EA7',
  ),
  StoreCourse(
    code: 'MA2201',
    name: '概率统计A',
    day: 2,
    begin: 1,
    end: 2,
    place: '主M403',
    teacher: '陈老师',
    color: '#438876',
  ),
  StoreCourse(
    code: 'CS2105',
    name: '数据结构与程序设计',
    day: 2,
    begin: 3,
    end: 4,
    place: '新主楼F201',
    teacher: '沈老师',
    color: '#C2185B',
    credit: '3.5',
  ),
  StoreCourse(
    code: 'EN2003',
    name: '大学英语Ⅲ',
    day: 2,
    begin: 6,
    end: 7,
    place: '一号楼204',
    teacher: '何老师',
    color: '#D9822B',
    credit: '2.0',
  ),
  StoreCourse(
    code: 'CS2101',
    name: '计算机组成原理',
    day: 3,
    begin: 3,
    end: 4,
    place: '主M201',
    teacher: '周老师',
    color: '#476FBD',
    credit: '4.0',
  ),
  StoreCourse(
    code: 'PE2001',
    name: '体育（羽毛球）',
    day: 3,
    begin: 6,
    end: 7,
    place: '体育馆',
    teacher: '马老师',
    color: '#2E7D4F',
    credit: '0.5',
  ),
  StoreCourse(
    code: 'CS2190',
    name: '程序设计实践',
    day: 3,
    begin: 11,
    end: 12,
    place: '新主楼G座机房',
    teacher: '沈老师',
    color: '#00838F',
    credit: '1.0',
    firstWeek: 3,
    lastWeek: 14,
  ),
  StoreCourse(
    code: 'MA2103',
    name: '离散数学',
    day: 4,
    begin: 1,
    end: 2,
    place: '主M305',
    teacher: '许老师',
    color: '#7B5EA7',
  ),
  StoreCourse(
    code: 'MA2201',
    name: '概率统计A',
    day: 4,
    begin: 3,
    end: 4,
    place: '主M403',
    teacher: '陈老师',
    color: '#438876',
  ),
  StoreCourse(
    code: 'HI2002',
    name: '中国近现代史纲要',
    day: 4,
    begin: 6,
    end: 8,
    place: '主M101',
    teacher: '刘老师',
    color: '#8D6E63',
  ),
  StoreCourse(
    code: 'AE1001',
    name: '航空航天概论',
    day: 5,
    begin: 3,
    end: 4,
    place: '新主楼A101',
    teacher: '高老师',
    color: '#1976D2',
    credit: '2.0',
  ),
];

StoreCourse storeCourse(String code) =>
    storeCourses.firstWhere((course) => course.code == code);

/// 返回本学期第 [week] 周、星期 [day]（1 为周一）的日期。
DateTime storeDate(int week, int day) =>
    storeTermStart.add(Duration(days: (week - 1) * 7 + day - 1));

String storeDateKey(DateTime date) =>
    '${date.year}-${_two(date.month)}-${_two(date.day)}';

/// 北京时间的 RFC 3339 时间戳，例如 2026-09-22T08:00:00+08:00。
String storeRfc3339(DateTime date, String hhmm) =>
    '${storeDateKey(date)}T$hhmm:00+08:00';

String _two(int value) => value.toString().padLeft(2, '0');

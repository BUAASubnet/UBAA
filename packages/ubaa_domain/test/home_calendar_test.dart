import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('排课缺少星期不能当作目标日期无课', () {
    final result = homeProjectScheduleDay(
      const FeatureResult.success(
        details: [
          FeatureDetail(
            title: '日期未明课程',
            presentation: ScheduleCoursePresentation(courseCode: 'a'),
          ),
        ],
      ),
      calendarWeek(8, '2026-10-26', '2026-11-01'),
      DateTime(2026, 10, 26),
    );
    expect(result.error, isNotNull);
  });

  test('教学周按日期匹配跨周与年界，冲突和越界日期拒绝', () {
    final weeks = [
      calendarWeek(7, '2026-10-19', '2026-10-25'),
      calendarWeek(8, '2026-10-26', '2026-11-01'),
    ];
    expect(homeWeekOn(weeks, DateTime(2026, 10, 26))?.number, 8);
    expect(homeWeekOn([...weeks, weeks.last], DateTime(2026, 10, 26)), isNull);
    expect(homeWeekOn(weeks, DateTime(2026, 11, 2)), isNull);
    expect(homeParseDate('2026-02-30'), isNull);
    expect(
      homeWeekOn([
        calendarWeek(18, '2026-12-28', '2027-01-03'),
      ], DateTime(2027, 1, 1))?.number,
      18,
    );
  });
  test('时间边界与缺失时间不把课程误判为全部结束', () {
    const course = TodayCoursePresentation(time: '09:50-12:15');
    final date = DateTime(2026, 10, 25);
    expect(
      homeCourseStatus(course, date, DateTime(2026, 10, 25, 9, 49)),
      '未开始',
    );
    expect(
      homeCourseStatus(course, date, DateTime(2026, 10, 25, 9, 50)),
      '进行中',
    );
    expect(
      homeCourseStatus(course, date, DateTime(2026, 10, 25, 12, 15)),
      '已结束',
    );
    expect(homeCoursesFinished([], date, DateTime(2026, 10, 25, 20)), isFalse);
    expect(
      homeCoursesFinished(
        const [
          FeatureDetail(
            title: '未定',
            presentation: TodayCoursePresentation(time: '09:50-待定'),
          ),
        ],
        date,
        DateTime(2026, 10, 25, 20),
      ),
      isFalse,
    );
    expect(homeCoursePeriod('24:00-25:00', date), isNull);
    expect(homeCoursePeriod('12:00-09:00', date), isNull);
    expect(homeCampusTime(DateTime.utc(2026, 10, 25, 16)).day, 26);
  });
  test('周课表只投影目标星期，不把周二课程显示到周一', () {
    final result = homeProjectScheduleDay(
      const FeatureResult.success(
        details: [
          FeatureDetail(
            title: '周一课',
            presentation: ScheduleCoursePresentation(
              courseCode: 'a',
              dayOfWeek: 1,
              beginTime: '08:00',
              endTime: '09:35',
            ),
          ),
          FeatureDetail(
            title: '周二课',
            presentation: ScheduleCoursePresentation(
              courseCode: 'b',
              dayOfWeek: 2,
            ),
          ),
        ],
      ),
      calendarWeek(8, '2026-10-26', '2026-11-01'),
      DateTime(2026, 10, 26),
    );
    expect(result.details.single.title, '周一课');
    expect((result.overview! as HomeScheduleOverview).date, '2026-10-26');
  });
}

WeekPresentation calendarWeek(int number, String start, String end) =>
    WeekPresentation(
      requestTerm: 'term',
      responseTerm: 'term',
      number: number,
      current: number == 7,
      startDate: start,
      endDate: end,
    );

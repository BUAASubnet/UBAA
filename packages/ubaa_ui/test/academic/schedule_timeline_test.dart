import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../coursework_content_test.dart' show showFeature;

void main() {
  for (final width in [390.0, 834.0, 1280.0]) {
    testWidgets('空周完整时间轴在$width宽度保持可见且无需额外查询', (tester) async {
      final queries = <FeatureQuery>[];
      await showFeature(
        tester,
        FeatureId.schedule,
        [],
        queries,
        size: Size(width, 900),
        query: const FeatureQuery(
          view: FeatureQueryView.scheduleWeek,
          term: '20261',
          week: 1,
        ),
        overview: ScheduleWeekOverview(
          code: '20261',
          sectionTimes: scheduleSectionTimes(
            courses: [],
            explicit: const [
              ScheduleSectionTime(1, '08:00', '08:45'),
              ScheduleSectionTime(2, '08:50', '09:35'),
              ScheduleSectionTime(3, '09:50', '10:35'),
            ],
          ),
        ),
      );
      expect(find.text('本周暂无课程'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('09:35'), findsOneWidget);
      expect(queries, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  test('旧缓存只在校方标准边界匹配时补14节，冲突时间不猜', () {
    final legacy = scheduleSectionTimes(code: '20261', courses: []);
    expect(legacy.length, 14);
    expect(legacy.last.end, '22:15');
    final conflict = scheduleSectionTimes(
      code: '20261',
      courses: const [
        ScheduleCoursePresentation(
          courseCode: 'demo',
          beginSection: 1,
          endSection: 2,
          beginTime: '09:00',
          endTime: '09:35',
        ),
      ],
    );
    expect(conflict.length, 12);
    expect(conflict.first.start, '09:00');
    final explicit = scheduleSectionTimes(
      code: '20261',
      courses: [],
      explicit: const [
        ScheduleSectionTime(1, '08:00', '08:45'),
        ScheduleSectionTime(1, '08:10', '08:45'),
      ],
    );
    expect(explicit.first.start, isNull);
    expect(explicit.first.end, '08:45');
  });
}

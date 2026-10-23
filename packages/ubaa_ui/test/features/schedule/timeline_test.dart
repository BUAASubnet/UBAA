import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../assignments/content_test.dart' show showFeature;

void main() {
  for (final width in [390.0, 834.0, 1280.0]) {
    testWidgets('稀疏课程在$width宽度补齐校历作息且不请求新数据', (tester) async {
      final queries = <FeatureQuery>[];
      await showFeature(
        tester,
        FeatureId.schedule,
        const [
          FeatureDetail(
            title: '合成课程',
            presentation: ScheduleCoursePresentation(
              courseCode: 'demo',
              dayOfWeek: 1,
              beginSection: 1,
              endSection: 2,
              beginTime: '08:00',
              endTime: '09:35',
            ),
          ),
        ],
        queries,
        size: Size(width, 900),
        query: const FeatureQuery(
          view: FeatureQueryView.scheduleWeek,
          term: 'term',
          week: 1,
        ),
      );
      expect(find.text('08:45'), findsOneWidget);
      expect(find.text('08:50'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('schedule-grid-scroll')),
        const Offset(0, -750),
      );
      await tester.pumpAndSettle();
      expect(find.text('22:15').hitTestable(), findsOneWidget);
      expect(queries, isEmpty);
      expect(tester.takeException(), isNull);
    });
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
  test('本科旧缓存补齐14节，明确时间优先且冲突不猜', () {
    final legacy = scheduleSectionTimes(code: 'fixture-student', courses: []);
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
    expect(conflict.length, 14);
    expect(conflict[9].end, '18:15');
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/common/feature_detail.dart';
import 'package:ubaa_ui/src/features/schedule/content.dart';
import '../assignments/content_test.dart' show showFeature;

void main() {
  testWidgets('空周在在线、缓存与刷新状态之间保留网格和滚动位置', (tester) async {
    const query = FeatureQuery(
      view: FeatureQueryView.scheduleWeek,
      term: '20261',
      week: 5,
    );
    State? gridState;
    for (final status in [
      FeatureLoadStatus.empty,
      FeatureLoadStatus.stale,
      FeatureLoadStatus.loading,
      FeatureLoadStatus.success,
      FeatureLoadStatus.empty,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeatureDetailView(
              feature: FeatureId.schedule,
              bykcFilters: const BykcCourseFilters.defaults(),
              onBykcFiltersChanged: (_) async {},
              query: query,
              snapshot: FeatureSnapshot(
                feature: FeatureId.schedule,
                status: status,
                readContext: FeatureReadContext(
                  query: query,
                  requestRevision: 1,
                ),
                evidence: DataEvidence(
                  accountId: 'synthetic',
                  origin: DataOrigin.persisted,
                  fetchedAt: DateTime.utc(2026, 11, 12),
                  complete: true,
                  savedForOffline: true,
                ),
              ),
              onBack: () {},
              onRetry: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
      final grid = find.byType(ScheduleContent);
      expect(grid, findsOneWidget, reason: '$status 应继续显示空周');
      if (gridState == null) {
        gridState = tester.state(grid);
        await tester.drag(
          find.byKey(const ValueKey('schedule-grid-scroll')),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
      } else {
        expect(tester.state(grid), same(gridState));
        final scroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(const ValueKey('schedule-grid-scroll')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(scroll.position.pixels, greaterThan(0));
      }
    }
  });

  for (final width in [320.0, 390.0, 834.0, 1280.0]) {
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
      expect(find.text('08:00\n08:45'), findsOneWidget);
      expect(find.text('08:50\n09:35'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('schedule-grid-scroll')),
        const Offset(0, -750),
      );
      await tester.pumpAndSettle();
      expect(find.text('21:30\n22:15').hitTestable(), findsOneWidget);
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
      expect(find.text('08:00\n08:45'), findsOneWidget);
      expect(find.text('09:50\n10:35'), findsOneWidget);
      expect(queries, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}

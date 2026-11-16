import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/common/details/detail_list.dart';

void main() {
  testWidgets('跨过签到时间边界重新读取资格，缓存不自动取得写资格', (tester) async {
    var now = DateTime(2026, 11, 16, 9, 59, 59);
    final queries = <FeatureQuery>[];
    const course = BykcChosenPresentation(
      recordId: 7,
      courseId: 42,
      courseName: '合成签到课程',
      signStartDate: '2026-11-16 10:00:00',
      signEndDate: '2026-11-16 10:01:00',
      signOutStartDate: '2026-11-16 11:00:00',
      signOutEndDate: '2026-11-16 11:01:00',
    );
    await withClock(Clock(() => now), () async {
      Future<void> mount(bool online) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeatureDetailList(
              feature: FeatureId.bykc,
              isBykcChosenDetail: true,
              details: [
                FeatureDetail(
                  title: '合成签到课程',
                  presentation: course,
                  actions: [
                    if (online)
                      const BykcSignAction(
                        courseId: 42,
                        kind: BykcSignKind.signIn,
                        eligibility: ActionEligibility.denied,
                        requiresCoordinates: false,
                      ),
                  ],
                ),
              ],
              onQuery: (query) async => queries.add(query),
            ),
          ),
        ),
      );
      await mount(true);
      now = DateTime(2026, 11, 16, 10);
      await tester.pump(const Duration(seconds: 5));
      expect(queries.single.courseId, '42');
      expect(queries.single.view, FeatureQueryView.bykcChosenCourses);
      await tester.pump(const Duration(seconds: 5));
      expect(queries, hasLength(1));
      now = DateTime(2026, 11, 16, 10, 1, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(queries, hasLength(2));
      now = DateTime(2026, 11, 16, 11);
      await tester.pump(const Duration(seconds: 5));
      expect(queries, hasLength(3));
      now = DateTime(2026, 11, 16, 11, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(queries, hasLength(3));
      await mount(false);
      now = DateTime(2026, 11, 16, 11, 1, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(queries, hasLength(3));
      await tester.pumpWidget(const SizedBox());
    });
  });
}

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/common/details/detail_list.dart';

void main() {
  testWidgets('跨过上课时间边界重新读取资格，缓存不自动取得写资格', (tester) async {
    // 时钟给出绝对时刻，边界按北京时间（UTC+8）计算。
    var now = DateTime.utc(2026, 11, 16, 1, 59, 59);
    final queries = <FeatureQuery>[];
    const course = BykcChosenPresentation(
      recordId: 7,
      courseId: 42,
      courseName: '合成上课课程',
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
                  title: '合成上课课程',
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
      now = DateTime.utc(2026, 11, 16, 2);
      await tester.pump(const Duration(seconds: 5));
      expect(queries.single.courseId, '42');
      expect(queries.single.view, FeatureQueryView.bykcChosenCourses);
      await tester.pump(const Duration(seconds: 5));
      expect(queries, hasLength(1));
      now = DateTime.utc(2026, 11, 16, 2, 1, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(queries, hasLength(2));
      now = DateTime.utc(2026, 11, 16, 3);
      await tester.pump(const Duration(seconds: 5));
      expect(queries, hasLength(3));
      now = DateTime.utc(2026, 11, 16, 3, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(queries, hasLength(3));
      await mount(false);
      now = DateTime.utc(2026, 11, 16, 3, 1, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(queries, hasLength(3));
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('设备不在东八区时仍按北京时间判断下课边界', (tester) async {
    // 时钟给出绝对时刻；上游时间是北京时间文本，不能按设备时区解释。
    var now = DateTime.utc(2026, 11, 16, 2, 59, 59);
    final queries = <FeatureQuery>[];
    await withClock(Clock(() => now), () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeatureDetailList(
              feature: FeatureId.bykc,
              isBykcChosenDetail: true,
              details: [_chosen(signOut: ActionEligibility.denied)],
              onQuery: (query) async => queries.add(query),
            ),
          ),
        ),
      );
      now = DateTime.utc(2026, 11, 16, 3);
      await tester.pump(const Duration(seconds: 5));
      expect(queries, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('已选列表也在上课时间边界重新读取当前列表', (tester) async {
    var now = DateTime.utc(2026, 11, 16, 2, 59, 59);
    final queries = <FeatureQuery>[];
    const listQuery = FeatureQuery(view: FeatureQueryView.bykcChosenCourses);
    await withClock(Clock(() => now), () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeatureDetailList(
              feature: FeatureId.bykc,
              query: listQuery,
              details: [_chosen(signOut: ActionEligibility.denied)],
              onQuery: (query) async => queries.add(query),
            ),
          ),
        ),
      );
      now = DateTime.utc(2026, 11, 16, 3);
      await tester.pump(const Duration(seconds: 5));
      expect(queries.single.view, FeatureQueryView.bykcChosenCourses);
      expect(queries.single.courseId, isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('已选卡片在可上课或可下课时直接提供对应按钮', (tester) async {
    final signed = <BykcSignAction>[];
    Future<void> mount(FeatureDetail detail) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeatureDetailList(
            feature: FeatureId.bykc,
            query: const FeatureQuery(view: FeatureQueryView.bykcChosenCourses),
            details: [detail],
            onBykcWrite: (_, __) async {},
            onBykcSignWrite: (action) async => signed.add(action),
          ),
        ),
      ),
    );

    await mount(_chosen(signOut: ActionEligibility.allowed));
    expect(find.text('退选'), findsNothing);
    await tester.tap(find.text('下课'));
    expect(signed.single.kind, BykcSignKind.signOut);

    await mount(_chosen(signIn: ActionEligibility.allowed));
    await tester.tap(find.text('上课'));
    expect(signed.last.kind, BykcSignKind.signIn);

    await mount(_chosen());
    expect(find.text('上课'), findsNothing);
    expect(find.text('下课'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '退选'), findsOneWidget);
  });
}

FeatureDetail _chosen({
  ActionEligibility signIn = ActionEligibility.denied,
  ActionEligibility signOut = ActionEligibility.denied,
}) => FeatureDetail(
  title: '合成上课课程',
  presentation: const BykcChosenPresentation(
    recordId: 7,
    courseId: 42,
    courseName: '合成上课课程',
    signStartDate: '2026-11-16 10:00:00',
    signEndDate: '2026-11-16 10:10:00',
    signOutStartDate: '2026-11-16 11:00:00',
    signOutEndDate: '2026-11-16 11:10:00',
  ),
  actions: [
    const BykcDeselectAction(
      courseId: 42,
      eligibility: ActionEligibility.denied,
    ),
    BykcSignAction(
      courseId: 42,
      kind: BykcSignKind.signIn,
      eligibility: signIn,
      requiresCoordinates: false,
    ),
    BykcSignAction(
      courseId: 42,
      kind: BykcSignKind.signOut,
      eligibility: signOut,
      requiresCoordinates: false,
    ),
  ],
);

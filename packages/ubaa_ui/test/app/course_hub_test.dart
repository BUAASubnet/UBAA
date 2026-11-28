import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/features/course_hub/entries.dart';
import 'package:ubaa_ui/src/features/course_hub/study_landing.dart';
import 'package:ubaa_ui/src/features/schedule/detail.dart';

void main() {
  const query = FeatureQuery(
    view: FeatureQueryView.spocDetail,
    assignmentId: 'task',
  );
  const task = CourseHubAssignment(
    feature: FeatureId.spoc,
    detail: FeatureDetail(
      title: '合成练习',
      presentation: SpocAssignmentPresentation(
        courseId: 'k',
        courseName: '合成课程',
        assignmentId: 'task',
        status: AssignmentSubmissionStatus.unsubmitted,
        statusText: '未提交',
      ),
      readNavigation: FeatureReadNavigation(
        feature: FeatureId.spoc,
        query: query,
      ),
    ),
  );
  const snapshot = CourseHubSnapshot(
    termCode: 'term',
    courses: [
      CourseHubCourse(
        key: 'code:A',
        name: '合成课程',
        courseCode: 'A',
        credit: null,
        teachers: [],
        slots: [],
        nextClass: null,
        spocCourses: [],
        judgeLinks: [],
        assignments: [task],
        exams: [],
        grades: [],
      ),
    ],
    allAssignments: [task],
  );
  testWidgets('课表弹层只打开同学期同代码的课程', (tester) async {
    String? opened;
    for (final term in ['old', 'term']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourseHubEntries(
              snapshot: snapshot,
              term: term,
              open: (key) => opened = key,
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => uiShowScheduleDetails(
                    context,
                    const FeatureDetail(
                      title: '合成排课',
                      presentation: ScheduleCoursePresentation(courseCode: 'A'),
                    ),
                  ),
                  child: const Text('排课详情'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('排课详情'));
      await tester.pumpAndSettle();
      if (term == 'old') {
        expect(find.text('进入课程'), findsNothing);
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.text('进入课程'));
        expect(opened, 'code:A');
      }
      await tester.pumpAndSettle();
    }
  });

  testWidgets('从课程主页返回后学习列表恢复到原滚动位置', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 874);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final hub = ValueNotifier(
      CourseHubSnapshot(
        termCode: 'term',
        courses: [
          for (var index = 0; index < 24; index++)
            CourseHubCourse(
              key: 'course-$index',
              name: '合成课程 $index',
              courseCode: null,
              credit: null,
              teachers: const [],
              slots: const [],
              nextClass: null,
              spocCourses: const [],
              judgeLinks: const [],
              assignments: const [],
              exams: const [],
              grades: const [],
            ),
        ],
      ),
    );
    addTearDown(hub.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UbaaMainShell(
          user: const UserSummary(username: 'synthetic'),
          initialDestination: UiDestination.study,
          courseHub: hub,
          routePolicy: RoutePolicy.direct,
          activeRoutes: const [ConnectionMode.direct],
          snapshots: const {},
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onRoutePolicyChanged: (_) {},
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byType(CourseHubLanding),
      matching: find.byType(Scrollable),
    );
    final course = find.byKey(const ValueKey('course-hub-course-course-17'));
    await tester.scrollUntilVisible(course, 300, scrollable: scrollable);
    await tester.pumpAndSettle();
    final before = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(before, greaterThan(0));
    await tester.tap(course.hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(CourseHubCoursePage), findsOneWidget);
    expect(scrollable, findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      closeTo(before, 0.1),
    );
    expect(course.hitTestable(), findsOneWidget);
  });
  for (final width in [402.0, 1100.0]) {
    testWidgets('课程、全部作业和来源导航 $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 874);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final queries = <FeatureQuery>[];
      var needs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: UbaaMainShell(
            user: const UserSummary(username: "synthetic"),
            initialDestination: UiDestination.study,
            courseHub: ValueNotifier(snapshot),
            onNeedCourseHub: () => needs++,
            routePolicy: RoutePolicy.direct,
            activeRoutes: const [ConnectionMode.direct],
            snapshots: {
              for (final feature in FeatureId.values)
                feature: FeatureSnapshot(feature: feature),
            },
            onRefresh: () async {},
            onRetryFeature: (_) async {},
            onRoutePolicyChanged: (_) {},
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onFeatureQuery: (_, value) async {
              queries.add(value);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(String label) async {
        final item = find.text(label).hitTestable().last;
        await tester.tap(item);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      Future<void> back() async {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }

      expect(needs, 1);
      await tester.tap(find.byKey(const ValueKey('course-hub-quick-schedule')));
      await tester.pump();
      expect(needs, 1);
      await back();
      for (final label in ['合成课程', '作业']) {
        await tap(label);
        await tap('合成练习');
        expect(queries.last, query);
        if (width > 600 && label == '合成课程') {
          await tester.tap(find.byTooltip('返回').hitTestable().first);
          await tester.pumpAndSettle();
        } else {
          await back();
        }
        expect(find.text('合成练习').hitTestable(), findsOneWidget);
        await back();
      }
      await tap('按来源浏览');
      await tap(FeatureId.signin.title);
      expect(
        find.widgetWithText(AppBar, FeatureId.signin.title),
        findsOneWidget,
      );
    });
  }
}

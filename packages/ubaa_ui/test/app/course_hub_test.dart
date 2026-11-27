import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/features/course_hub/entries.dart';
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
  for (final width in [402.0, 1100.0]) {
    testWidgets('课程、全部作业和来源导航 $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 874);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final queries = <FeatureQuery>[];
      await tester.pumpWidget(
        MaterialApp(
          home: UbaaMainShell(
            user: const UserSummary(username: "synthetic"),
            initialDestination: UiDestination.study,
            courseHub: ValueNotifier(snapshot),
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

      for (final label in ['合成课程', '全部作业']) {
        await tap(label);
        await tap('合成练习');
        expect(queries.last, query);
        if (width > 600) {
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

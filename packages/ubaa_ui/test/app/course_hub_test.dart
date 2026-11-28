import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/common/read_navigator.dart'
    show FeatureReadNavigator;
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
  testWidgets('课程中心及按来源浏览的功能入口与校园页互不重复', (tester) async {
    await _mountCourseHub(tester, width: 402, snapshot: snapshot);

    final studyRoot = find.byKey(const PageStorageKey('course-hub-landing'));
    final study = await _observedFeatures(
      tester,
      studyRoot,
      shortTitles: const {
        FeatureId.schedule: '课表',
        FeatureId.exam: '考试',
        FeatureId.grades: '成绩',
      },
    );
    final sources = find.byKey(const ValueKey('course-hub-open-sources'));
    final studyScroll = find.descendant(
      of: studyRoot,
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(studyScroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(sources, 220, scrollable: studyScroll);
    await tester.tap(sources);
    await tester.pumpAndSettle();
    study.addAll(
      await _observedFeatures(
        tester,
        find.byKey(const ValueKey('course-hub-sources')),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(NavigationDestination, UiDestination.campus.label),
    );
    await tester.pumpAndSettle();
    final campus = await _observedFeatures(
      tester,
      find.byType(CustomScrollView),
    );
    expect(study.intersection(campus), isEmpty);
    expect(study, unorderedEquals(UiDestination.study.features));
    expect(campus, unorderedEquals(UiDestination.campus.features));
  });

  for (final width in [402.0, 1100.0]) {
    testWidgets('课程、全部作业和来源导航 $width', (tester) async {
      final queries = <FeatureQuery>[];
      var needs = 0;
      await _mountCourseHub(
        tester,
        width: width,
        snapshot: snapshot,
        onNeedCourseHub: () => needs++,
        onFeatureQuery: (_, value) async {
          queries.add(value);
        },
      );
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

Future<void> _mountCourseHub(
  WidgetTester tester, {
  required double width,
  required CourseHubSnapshot snapshot,
  VoidCallback? onNeedCourseHub,
  Future<void> Function(FeatureId, FeatureQuery)? onFeatureQuery,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 874);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final hub = ValueNotifier(snapshot);
  addTearDown(hub.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: UbaaMainShell(
        user: const UserSummary(username: 'synthetic'),
        initialDestination: UiDestination.study,
        courseHub: hub,
        onNeedCourseHub: onNeedCourseHub,
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
        onFeatureQuery: onFeatureQuery,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<Set<FeatureId>> _observedFeatures(
  WidgetTester tester,
  Finder view, {
  Map<FeatureId, String> shortTitles = const {},
}) async {
  final entries = <String, FeatureId>{};
  final scrollable = find.descendant(
    of: view,
    matching: find.byType(Scrollable),
  );
  Finder entry(String label) =>
      find.descendant(of: view, matching: find.text(label));
  final position = tester.state<ScrollableState>(scrollable).position;
  while (true) {
    for (final feature in FeatureId.values) {
      for (final label in [feature.title, ?shortTitles[feature]]) {
        if (entry(label).evaluate().isNotEmpty) entries[label] = feature;
      }
    }
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(
      (position.pixels + 220).clamp(0.0, position.maxScrollExtent).toDouble(),
    );
    await tester.pumpAndSettle();
  }

  final opened = <FeatureId>{};
  for (final MapEntry(key: label, value: expected) in entries.entries) {
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(entry(label), 220, scrollable: scrollable);
    await tester.tap(entry(label));
    // 合成快照停在初始加载状态，只推进进入过渡需要的帧。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final navigator = tester.widget<FeatureReadNavigator>(
      find.byType(FeatureReadNavigator),
    );
    final feature = navigator.snapshot.feature;
    expect(feature, expected, reason: '点击 $label 后打开的领域');
    opened.add(feature);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }
  return opened;
}

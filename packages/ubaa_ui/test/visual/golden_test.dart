import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/features/grades/cards.dart';
import 'package:ubaa_ui/src/features/schedule/content.dart';

// 按不同布局选择代表，不为同一种通用详情卡遍历功能名和主题笛卡尔积。
// 跨宽度的导航、筛选、语义和溢出行为继续由对应领域测试负责。
void main() {
  _visual(
    'menu_desktop_dark',
    const Size(1280, 800),
    _menu,
    content: UbaaMainShell,
    dark: true,
  );
  _visual(
    'menu_phone_large',
    const Size(390, 844),
    _menu,
    content: NavigationBar,
    scale: 1.3,
  );
  _visual(
    'schedule_desktop',
    const Size(1280, 800),
    _schedule,
    content: ScheduleContent,
  );
  _visual(
    'schedule_phone_dark_large',
    const Size(390, 844),
    _schedule,
    content: ScheduleContent,
    dark: true,
    scale: 1.3,
  );
  _visual(
    'grades_tablet',
    const Size(768, 1024),
    _grades,
    content: GradeSummaryCard,
    scale: 1.3,
  );
  _visual(
    'error_phone_large',
    const Size(390, 844),
    _error,
    content: FriendlyErrorCard,
    scale: 1.3,
  );
}

void _visual(
  String name,
  Size size,
  Widget Function() build, {
  required Type content,
  bool dark = false,
  double scale = 1,
}) {
  testWidgets('代表性布局 $name', (tester) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await withClock(Clock.fixed(DateTime(2026, 9, 9)), () async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('visual-scene'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? UbaaTheme.dark() : UbaaTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: build(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(content), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('visual-scene')),
        matchesGoldenFile('../goldens/$name.png'),
      );
    });
  });
}

Widget _menu() => UbaaMainShell(
  user: const UserSummary(username: 'synthetic', displayName: '测试同学'),
  initialDestination: UiDestination.academic,
  snapshots: {
    for (final feature in FeatureId.values)
      feature: FeatureSnapshot(feature: feature),
  },
  routePolicy: RoutePolicy.auto,
  telemetryEnabled: false,
  onRefresh: () async {},
  onRetryFeature: (_) async {},
  onLogout: () async {},
  onLogoutAndClearAccount: () async {},
  onRoutePolicyChanged: (_) {},
  onTelemetryChanged: (_) {},
);

const _courses = [
  FeatureDetail(
    title: '计算机系统与程序设计综合实验',
    presentation: ScheduleCoursePresentation(
      courseCode: 'synthetic-1',
      dayOfWeek: 1,
      beginSection: 1,
      endSection: 2,
      beginTime: '08:00',
      endTime: '09:35',
      place: '教学楼 A201',
      weeksAndTeachers: '1–16周 · 测试教师',
      color: '#476fbd',
    ),
  ),
  FeatureDetail(
    title: '高等数学',
    presentation: ScheduleCoursePresentation(
      courseCode: 'synthetic-2',
      dayOfWeek: 3,
      beginSection: 3,
      endSection: 4,
      beginTime: '09:50',
      endTime: '11:25',
      place: '教学楼 B301',
      color: '#7b5ea7',
    ),
  ),
  FeatureDetail(
    title: '航空航天概论',
    presentation: ScheduleCoursePresentation(
      courseCode: 'synthetic-3',
      dayOfWeek: 5,
      beginSection: 5,
      endSection: 6,
      beginTime: '14:00',
      endTime: '15:35',
      place: '教学楼 C402',
      color: '#438876',
    ),
  ),
];

Widget _schedule() => Scaffold(
  appBar: AppBar(title: const Text('课表')),
  body: ScheduleContent(
    details: _courses,
    timeline: ScheduleWeekOverview(
      code: 'synthetic-term',
      sectionTimes: scheduleSectionTimes(
        courses: _courses.map(
          (d) => d.presentation! as ScheduleCoursePresentation,
        ),
      ),
    ),
  ),
);

const _gradeDetails = [
  FeatureDetail(
    title: '计算机系统与程序设计综合实验',
    presentation: GradePresentation(
      courseName: '计算机系统与程序设计综合实验',
      courseCode: 'SYNTHETIC-101',
      score: '92',
      credit: 4,
      gradePoint: '4.0',
      courseType: '必修',
      scoreType: '百分制',
    ),
  ),
  FeatureDetail(
    title: '工程实践',
    presentation: GradePresentation(
      courseName: '工程实践',
      courseCode: 'SYNTHETIC-102',
      score: '优秀',
      credit: 2,
      courseType: '选修',
      scoreType: '五级制',
    ),
  ),
  FeatureDetail(
    title: '综合课程设计与创新实践',
    presentation: GradePresentation(
      courseName: '综合课程设计与创新实践',
      courseCode: 'SYNTHETIC-103',
      credit: 3,
      courseType: '必修',
    ),
  ),
];

Widget _grades() => Scaffold(
  appBar: AppBar(title: const Text('课程成绩')),
  body: ListView(
    padding: const EdgeInsets.all(16),
    children: [
      GradeSummaryCard(
        title: '本学期',
        showCourseAndCredits: true,
        statistics: GradeStatistics.calculate(
          _gradeDetails.map((d) => d.presentation! as GradePresentation),
        ),
      ),
      for (final detail in _gradeDetails) ...[
        const SizedBox(height: 12),
        GradeCard(detail: detail),
      ],
    ],
  ),
);

Widget _error() => Scaffold(
  appBar: AppBar(title: const Text('课程查询')),
  body: ListView(
    padding: const EdgeInsets.all(16),
    children: [
      FriendlyErrorCard(
        error: const UiError(
          code: UbaaErrorCode.networkError,
          kind: UbaaErrorKind.network,
          title: '暂时无法连接',
          message: '请检查网络连接后重试，已保存的课程仍可查看。',
          issueId: 'UBAA-synthetic-1',
          retryable: true,
        ),
        onRetry: () {},
      ),
    ],
  ),
);

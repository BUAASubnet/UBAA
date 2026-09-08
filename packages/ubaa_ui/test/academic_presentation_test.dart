import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('不同领域的展示模型仍可通过通用详情读取原字段', (tester) async {
    await _show(tester, FeatureId.classroom, const [
      FeatureDetail(
        title: '保留的详情',
        fields: [FeatureField(label: '原字段', value: '原值')],
        presentation: GradePresentation(score: '80'),
      ),
    ]);
    expect(find.text('原值'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('宽考试沿旧时间线且已结束可展开，非标准日期保留', (tester) async {
    await _show(tester, FeatureId.exam, const [
      FeatureDetail(
        title: '原顺序第一',
        presentation: ExamPresentation(
          arranged: true,
          date: '教务待确认',
          startTime: '午后',
        ),
      ),
      FeatureDetail(
        title: '原顺序第二',
        presentation: ExamPresentation(arranged: true, date: '2020-01-01'),
      ),
      FeatureDetail(
        title: '未安排课程',
        presentation: ExamPresentation(arranged: false),
      ),
    ], width: 1280);
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('已结束考试 (1)'), findsOneWidget);
    expect(find.text('未安排/其他'), findsOneWidget);
    expect(find.text('原顺序第二'), findsNothing);
    await tester.tap(find.text('已结束考试 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('原顺序第二'), findsOneWidget);
    await tester.tap(find.text('原顺序第一'));
    await tester.pumpAndSettle();
    expect(find.text('教务待确认'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('平板成绩主要列无需横滚且次要字段可本地打开', (tester) async {
    await _show(
      tester,
      FeatureId.grades,
      const [
        FeatureDetail(
          title: '可打开的课程',
          presentation: GradePresentation(
            courseCode: 'CS-X',
            score: '80',
            gradePoint: '3',
            credit: 2,
            scoreType: '百分制',
            termCode: '2026-1',
          ),
        ),
        FeatureDetail(title: '等待公布的课程', presentation: GradePresentation()),
      ],
      width: 834,
      textScale: 1.3,
    );
    expect(find.byType(DataTable), findsNWidgets(2));
    expect(
      tester.getRect(find.byType(DataTable).first).right,
      lessThanOrEqualTo(834),
    );
    expect(find.text('待出成绩 · 本页1门'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsNothing,
    );
    await tester.tap(find.text('可打开的课程'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('更多信息').last);
    await tester.pumpAndSettle();
    expect(find.text('百分制'), findsOneWidget);
    expect(find.text('2026-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽教室楼层导航只筛当前结果并可恢复全部', (tester) async {
    await _show(tester, FeatureId.classroom, const [
      FeatureDetail(
        title: '一层教室',
        presentation: ClassroomPresentation(
          roomId: 'a',
          floorId: 'F1',
          floorName: '一层',
          availableSections: '1,13',
        ),
      ),
      FeatureDetail(
        title: '二层教室',
        presentation: ClassroomPresentation(
          roomId: 'b',
          floorId: 'F2',
          floorName: '二层',
          availableSections: '3',
        ),
      ),
    ], width: 1280);
    await tester.tap(find.widgetWithText(ListTile, '二层'));
    await tester.pumpAndSettle();
    expect(find.text('一层教室'), findsNothing);
    expect(find.text('二层教室'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '全部（本页）'));
    await tester.pumpAndSettle();
    expect(find.text('一层教室'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('宽屏成绩长课程名在1.3文字完整伸展并显示课程编号', (tester) async {
    final title = List.filled(12, '跨学科课程中的实践与理论').join('');
    await _show(
      tester,
      FeatureId.grades,
      [
        FeatureDetail(
          title: title,
          presentation: const GradePresentation(
            courseCode: 'CODE-FULL',
            score: '优秀',
          ),
        ),
      ],
      width: 1280,
      textScale: 1.3,
    );
    expect(find.text('CODE-FULL'), findsOneWidget);
    final titleRect = tester.getRect(find.text(title));
    expect(titleRect.height, greaterThan(112));
    expect(
      tester.getRect(find.byType(DataTable)).bottom,
      greaterThan(titleRect.bottom),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('周课表使用周几节次并保留时间待确认课程', (tester) async {
    await _show(tester, FeatureId.schedule, const [
      FeatureDetail(
        title: '程序设计',
        presentation: ScheduleCoursePresentation(
          courseCode: 'CS-1',
          dayOfWeek: 2,
          beginSection: 3,
          endSection: 4,
          beginTime: '10:00',
          endTime: '11:40',
          place: '合成教学楼A203',
        ),
      ),
      FeatureDetail(
        title: '时间字段异常的课程',
        presentation: ScheduleCoursePresentation(
          courseCode: 'CS-2',
          dayOfWeek: 9,
          beginSection: 4,
          endSection: 2,
        ),
      ),
    ]);
    expect(
      find.descendant(
        of: find.widgetWithText(Card, '程序设计'),
        matching: find.text('星期二'),
      ),
      findsOneWidget,
    );
    expect(find.text('第3–4节'), findsOneWidget);
    expect(find.text('10:00–11:40'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('时间待确认'), findsOneWidget);
    expect(find.text('时间字段异常的课程'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('考试仅有开始时间仍可读且保留座位和安排状态', (tester) async {
    await _show(tester, FeatureId.exam, const [
      FeatureDetail(
        title: '高等数学',
        presentation: ExamPresentation(
          arranged: true,
          date: '2999-09-08',
          startTime: '09:00',
          seat: 'A018',
        ),
      ),
      FeatureDetail(
        title: '大学英语',
        presentation: ExamPresentation(arranged: false),
      ),
    ]);
    expect(find.text('09:00 开始'), findsOneWidget);
    expect(find.text('座位 A018'), findsOneWidget);
    expect(find.text('时间待公布'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[390, 1280]) {
    testWidgets('成绩在$width宽度保留非数值得分且不推算绩点', (tester) async {
      await _show(tester, FeatureId.grades, const [
        FeatureDetail(
          title: '实践课程',
          presentation: GradePresentation(
            score: '通过',
            gradePoint: '优秀',
            credit: 2.5,
          ),
        ),
        FeatureDetail(title: '待出课程', presentation: GradePresentation()),
      ], width: width);
      expect(find.text('通过'), findsOneWidget);
      expect(find.text('优秀'), findsOneWidget);
      expect(find.text('待出成绩'), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('空教室明确显示楼层与完整节次令牌', (tester) async {
    await _show(tester, FeatureId.classroom, const [
      FeatureDetail(
        title: 'A203',
        presentation: ClassroomPresentation(
          roomId: 'room-3',
          floorId: 'F03',
          floorName: '三层',
          availableSections: '3,13',
        ),
      ),
    ]);
    expect(find.text('三层'), findsNWidgets(2));
    expect(find.text('第3节'), findsOneWidget);
    expect(find.text('第13节'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _show(
  WidgetTester tester,
  FeatureId feature,
  List<FeatureDetail> details, {
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: UbaaMainShell(
        initialTab: 1,
        user: const UserSummary(username: 'fixture-student'),
        snapshots: {
          for (final id in FeatureId.values)
            id: FeatureSnapshot(
              feature: id,
              status: FeatureLoadStatus.success,
              details: id == feature ? details : const [],
            ),
        },
        routePolicy: RoutePolicy.auto,
        telemetryEnabled: false,
        onRefresh: () async {},
        onRetryFeature: (_) async {},
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  final grid = find.byType(CustomScrollView);
  final card = find.descendant(
    of: grid,
    matching: find.widgetWithText(Card, feature.title),
  );
  await tester.scrollUntilVisible(
    card,
    200,
    scrollable: find.descendant(of: grid, matching: find.byType(Scrollable)),
  );
  await tester.tap(card);
  await tester.pumpAndSettle();
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'support/navigation.dart';

void main() {
  testWidgets('SPOC列表沿旧版只展示一次课程分组并把score标为分值', (tester) async {
    await showFeature(tester, FeatureId.spoc, [
      const FeatureDetail(
        title: '合成作业',
        presentation: SpocAssignmentPresentation(
          courseId: 'c',
          courseName: '合成课程',
          assignmentId: 'a',
          score: '10',
          status: AssignmentSubmissionStatus.unsubmitted,
          statusText: '未提交',
          dueTime: '2026-09-13 23:59',
        ),
        readNavigation: FeatureReadNavigation(
          feature: FeatureId.spoc,
          query: FeatureQuery(
            view: FeatureQueryView.spocDetail,
            assignmentId: 'a',
          ),
        ),
      ),
    ], []);
    expect(find.text('合成课程'), findsOneWidget);
    expect(find.textContaining('分值'), findsOneWidget);
    expect(find.text('成绩'), findsNothing);
  });
  testWidgets('签到缺少目标时明确说明且不从课程编号生成动作', (tester) async {
    await showFeature(tester, FeatureId.signin, [
      const FeatureDetail(
        title: '合成签到课',
        presentation: SigninPresentation(
          courseId: '课程不是签到目标',
          classBeginTime: '08:00',
          classEndTime: '09:40',
          signStatus: 0,
        ),
      ),
    ], []);
    expect(find.text('未提供签到目标，请刷新课程后重试。'), findsOneWidget);
    expect(find.text('准备签到'), findsNothing);
  });
  testWidgets('评教各端沿旧版课程行并保留未知资格说明', (tester) async {
    await showFeature(
      tester,
      FeatureId.evaluation,
      [
        const FeatureDetail(
          title: '合成课程',
          subtitle: '合成教师',
          presentation: EvaluationCoursePresentation(
            courseId: 'c',
            isEvaluated: false,
          ),
        ),
      ],
      [],
      size: const Size(1200, 1200),
    );
    expect(find.byType(DataTable), findsNothing);
    expect(find.byTooltip('课程详情'), findsOneWidget);
    expect(find.text('当前评教资格无法确认，请刷新后重试。'), findsOneWidget);
  });
  testWidgets('希冀选择已加载作业时课程和作业编号同时更新', (tester) async {
    final queries = <FeatureQuery>[];
    await showFeature(tester, FeatureId.judge, [
      judge('A'),
      judge('B'),
    ], queries);
    await openQueryPanel(tester);
    await tester.tap(find.text('作业列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业详情').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择已加载作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B 课程 · B 作业（B / same）'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '课程编号'))
          .controller!
          .text,
      'B',
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '作业编号'))
          .controller!
          .text,
      'same',
    );
    expect(queries, isEmpty);
  });
  testWidgets('混合未知模型不移除合法作业的选择入口', (tester) async {
    await showFeature(tester, FeatureId.judge, [
      judge('A'),
      const FeatureDetail(
        title: '未知模型但保留内容',
        fields: [FeatureField(label: '附加字段', value: '兼容内容')],
      ),
    ], []);
    expect(
      find.byKey(const ValueKey(('judge-selection', 'A', 'same'))),
      findsOneWidget,
    );
    expect(find.text('兼容内容'), findsOneWidget);
  });
  for (final size in [const Size(390, 1000), const Size(834, 1210)]) {
    testWidgets('长题目和长状态在 1.3 字号 ${size.width} 宽度不溢出', (tester) async {
      await showFeature(
        tester,
        FeatureId.judge,
        [
          FeatureDetail(
            title: '用于检查多行显示的合成作业标题' * 3,
            presentation: JudgeAssignmentPresentation(
              courseId: 'c',
              courseName: '合成课程',
              assignmentId: 'a',
              totalProblems: 1,
              submittedCount: 0,
              status: AssignmentSubmissionStatus.unknown,
              statusText: '上游返回的较长状态说明' * 4,
              isDetail: true,
              problems: [
                JudgeProblemPresentation(
                  name: '需要完整显示的长题目名称' * 8,
                  status: AssignmentSubmissionStatus.unknown,
                  statusText: '需要完整显示的题目状态' * 4,
                  score: '尚未公布',
                  maxScore: '尚未公布',
                ),
              ],
            ),
          ),
        ],
        [],
        query: const FeatureQuery(
          view: FeatureQueryView.judgeDetail,
          courseId: 'c',
          assignmentId: 'a',
        ),
        size: size,
        textScale: 1.3,
      );
      expect(find.byType(TextField), findsNothing);
      final problems = find.text('题目明细');
      await tester.scrollUntilVisible(
        problems,
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('SPOC 详情使用 typed 导航而非展示编号', (tester) async {
    final queries = <FeatureQuery>[];
    await showFeature(tester, FeatureId.spoc, [
      const FeatureDetail(
        title: '合成作业',
        fields: [FeatureField(label: '作业编号', value: '错误展示编号')],
        presentation: SpocAssignmentPresentation(
          courseId: 'c',
          courseName: '合成课程',
          assignmentId: 'a',
          status: AssignmentSubmissionStatus.unsubmitted,
          statusText: '未提交',
        ),
        readNavigation: FeatureReadNavigation(
          feature: FeatureId.spoc,
          query: FeatureQuery(
            view: FeatureQueryView.spocDetail,
            assignmentId: 'a',
          ),
        ),
      ),
    ], queries);
    await tester.tap(find.byTooltip('查看作业详情'));
    await tester.pump();
    expect(queries.single.assignmentId, 'a');
  });
  testWidgets('希冀跨课程同编号按 B 到 A 的选择顺序批量查询', (tester) async {
    final queries = <FeatureQuery>[];
    await showFeature(
      tester,
      FeatureId.judge,
      [judge('A'), judge('B')],
      queries,
      query: const FeatureQuery(includeExpired: true),
    );
    for (final course in ['B', 'A']) {
      final checkbox = find.byKey(
        ValueKey(('judge-selection', course, 'same')),
      );
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
    }
    await openQueryPanel(tester);
    await tester.enterText(find.widgetWithText(TextField, '筛选详情'), '没有匹配');
    await closeQueryPanel(tester);
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 份作业'), findsOneWidget);
    await tester.tap(find.text('查看所选作业'));
    await tester.pump();
    expect(queries.single.view, FeatureQueryView.judgeBatchDetails);
    expect(queries.single.judgeKeys.map((key) => key.courseId), ['B', 'A']);
    expect(queries.single.includeExpired, isTrue);
  });
  testWidgets('待评空列表仍展示全局评教进度', (tester) async {
    await showFeature(
      tester,
      FeatureId.evaluation,
      [],
      [],
      overview: const EvaluationProgressOverview(
        totalCourses: 12,
        evaluatedCourses: 12,
        pendingCourses: 0,
      ),
      query: const FeatureQuery(view: FeatureQueryView.evaluationPending),
    );
    expect(find.text('已评 12 / 12 门'), findsOneWidget);
    expect(find.text('待评 0 门'), findsOneWidget);
    expect(find.text('暂无${FeatureId.evaluation.title}数据'), findsOneWidget);
  });
  testWidgets('批量题目归属正确且可按题名筛选', (tester) async {
    await showFeature(
      tester,
      FeatureId.judge,
      [judge('A', detail: true), judge('B', detail: true)],
      [],
      query: const FeatureQuery(view: FeatureQueryView.judgeBatchDetails),
    );
    await openQueryPanel(tester);
    await tester.enterText(find.widgetWithText(TextField, '筛选详情'), 'B 的题目');
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'B 的题目',
      ),
      findsOneWidget,
    );
    expect(find.text('B 作业'), findsOneWidget);
    expect(find.text('A 作业'), findsNothing);
  });
}

FeatureDetail judge(String course, {bool detail = false}) => FeatureDetail(
  title: '$course 作业',
  presentation: JudgeAssignmentPresentation(
    courseId: course,
    courseName: '$course 课程',
    assignmentId: 'same',
    totalProblems: 1,
    submittedCount: 0,
    status: AssignmentSubmissionStatus.unsubmitted,
    statusText: '未提交',
    isDetail: detail,
    problems: detail
        ? [
            JudgeProblemPresentation(
              name: '$course 的题目',
              status: AssignmentSubmissionStatus.unsubmitted,
              statusText: '未提交',
            ),
          ]
        : [],
  ),
);
Future<void> showFeature(
  WidgetTester tester,
  FeatureId feature,
  List<FeatureDetail> details,
  List<FeatureQuery> queries, {
  FeatureQuery query = const FeatureQuery(),
  FeatureOverview? overview,
  Size size = const Size(800, 1200),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: UbaaMainShell(
        user: const UserSummary(username: 'fixture'),
        initialTab: ordinaryFeatureIds.contains(feature) ? 1 : 2,
        snapshots: {
          for (final id in FeatureId.values)
            id: id == feature
                ? FeatureSnapshot(
                    feature: id,
                    status: details.isEmpty
                        ? FeatureLoadStatus.empty
                        : FeatureLoadStatus.success,
                    details: details,
                    overview: overview,
                    readContext: FeatureReadContext(
                      query: query,
                      requestRevision: 1,
                    ),
                  )
                : FeatureSnapshot(feature: id),
        },
        routePolicy: RoutePolicy.auto,
        telemetryEnabled: false,
        onRefresh: () async {},
        onRetryFeature: (_) async {},
        onFeatureQuery: (_, query) async {
          queries.add(query);
        },
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  final card = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.widgetWithText(Card, feature.title),
  );
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
}

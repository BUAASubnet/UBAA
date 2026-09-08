import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'support/navigation.dart';

void main() {
  testWidgets('手机单项返回后更换搜索仍能选择另一课程作业', (tester) async {
    await showHarness(tester, size: const Size(402, 874));
    Future<void> search(String value) async {
      await openQueryPanel(tester);
      final field = find.widgetWithText(TextField, '筛选详情');
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await closeQueryPanel(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
    }

    await search('A 课程');
    final detail = find.text('查看作业详情');
    await Scrollable.ensureVisible(tester.element(detail), alignment: .5);
    await tester.pumpAndSettle();
    expect(detail.hitTestable(), findsOneWidget);
    await tester.tap(detail);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await search('B 课程');
    final choice = find.byKey(const ValueKey(('judge-selection', 'B', 'a')));
    if (choice.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        choice,
        100,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last,
      );
    }
    await Scrollable.ensureVisible(tester.element(choice), alignment: .5);
    await tester.pumpAndSettle();
    expect(choice.hitTestable(), findsOneWidget);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 份作业'), findsOneWidget);
  });
  testWidgets('批量详情返回保留父页选择顺序、筛选和过期条件且不重读', (tester) async {
    final state = await showHarness(tester);
    for (final course in ['B', 'A']) {
      final selection = find.byKey(ValueKey(('judge-selection', course, 'a')));
      await tester.ensureVisible(selection);
      await tester.tap(selection);
      await tester.pumpAndSettle();
    }
    await openQueryPanel(tester);
    await tester.enterText(find.widgetWithText(TextField, '筛选详情'), '作业');
    await closeQueryPanel(tester);
    await closeQueryPanel(tester);
    await tester.tap(find.text('查看所选作业'));
    await tester.pumpAndSettle();
    expect(state.queries.single.judgeKeys.map((key) => key.courseId), [
      'B',
      'A',
    ]);
    expect(state.queries.single.includeExpired, isTrue);
    expect(find.text('B 子作业'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(state.queries, hasLength(1));
    expect(find.text('已选择 2 份作业'), findsOneWidget);
    await openQueryPanel(tester);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '筛选详情'))
          .controller!
          .text,
      '作业',
    );
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '包含已过期作业'))
          .selected,
      isTrue,
    );
    await closeQueryPanel(tester);
    await tester.tap(find.text('查看所选作业'));
    await tester.pumpAndSettle();
    expect(state.queries.last.judgeKeys.map((key) => key.courseId), ['B', 'A']);
  });
  testWidgets('选择作业弹窗跨读取生命周期失效时不回填旧账号草稿', (tester) async {
    final state = await showHarness(tester);
    await openQueryPanel(tester);
    await tester.tap(find.text('作业列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业详情').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择已加载作业'));
    await tester.pumpAndSettle();
    state.invalidate();
    await tester.pumpAndSettle();
    await tester.tap(find.text('B 课程 · B 作业（B / a）'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '课程编号'))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '作业编号'))
          .controller!
          .text,
      isEmpty,
    );
    expect(state.queries, isEmpty);
  });
}

Future<_HarnessState> showHarness(
  WidgetTester tester, {
  Size size = const Size(800, 1200),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: _Harness()));
  await tester.pumpAndSettle();
  final card = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.widgetWithText(Card, FeatureId.judge.title),
  );
  await tester.ensureVisible(card);
  await tester.tap(card);
  await tester.pumpAndSettle();
  return tester.state<_HarnessState>(find.byType(_Harness));
}

class _Harness extends StatefulWidget {
  const _Harness();
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int epoch = 0;
  int revision = 1;
  final queries = <FeatureQuery>[];
  FeatureSnapshot snapshot = FeatureSnapshot(
    feature: FeatureId.judge,
    status: FeatureLoadStatus.success,
    readContext: FeatureReadContext(
      query: const FeatureQuery(includeExpired: true),
      requestRevision: 1,
    ),
    details: [
      for (final course in ['A', 'B']) assignment(course),
    ],
  );
  static FeatureDetail assignment(String course, {bool child = false}) =>
      FeatureDetail(
        title: '$course ${child ? '子作业' : '作业'}',
        presentation: JudgeAssignmentPresentation(
          courseId: course,
          courseName: '$course 课程',
          assignmentId: 'a',
          totalProblems: 1,
          submittedCount: 0,
          status: AssignmentSubmissionStatus.unsubmitted,
          statusText: '未提交',
          isDetail: child,
          problems: child
              ? [
                  JudgeProblemPresentation(
                    name: '$course 的题目',
                    status: AssignmentSubmissionStatus.unsubmitted,
                    statusText: '未提交',
                  ),
                ]
              : [],
        ),
        readNavigation: child
            ? null
            : FeatureReadNavigation(
                feature: FeatureId.judge,
                query: FeatureQuery(
                  view: FeatureQueryView.judgeDetail,
                  courseId: course,
                  assignmentId: 'a',
                  includeExpired: true,
                ),
              ),
      );
  void invalidate() => setState(() {
    epoch++;
  });
  Future<void> query(FeatureId feature, FeatureQuery query) async {
    queries.add(query);
    setState(() {
      snapshot = FeatureSnapshot(
        feature: feature,
        status: FeatureLoadStatus.success,
        readContext: FeatureReadContext(
          query: query,
          requestRevision: ++revision,
        ),
        details: [
          for (final key in query.judgeKeys)
            assignment(key.courseId, child: true),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) => UbaaMainShell(
    user: const UserSummary(username: 'fixture'),
    initialTab: 1,
    snapshots: {
      for (final id in FeatureId.values)
        id: id == FeatureId.judge ? snapshot : FeatureSnapshot(feature: id),
    },
    readCacheEpoch: epoch,
    routePolicy: RoutePolicy.auto,
    telemetryEnabled: false,
    onRefresh: () async {},
    onRetryFeature: (_) async {},
    onFeatureQuery: query,
    onLogout: () async {},
    onLogoutAndClearAccount: () async {},
    onRoutePolicyChanged: (_) {},
    onTelemetryChanged: (_) {},
  );
}

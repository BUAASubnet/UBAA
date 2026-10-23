import 'package:ubaa_ui/src/features/coursework/assignment_content.dart'
    show AssignmentCard;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart';

void main() {
  testWidgets('希冀首批在继续加载时可见可打开，返回后继续未完成列表', (tester) async {
    final state = await showHarness(tester);
    state.progressive();
    await tester.pump();
    expect(find.text('A 作业'), findsOneWidget);
    final target = find.byType(AssignmentCard).first;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(state.queries.single.view, FeatureQueryView.judgeDetail);
    expect(state.queries.single.courseId, 'A');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(state.queries, hasLength(2));
    expect(state.queries.last.view, FeatureQueryView.summary);
  });
  testWidgets('手机单项返回后更换搜索仍能打开另一课程作业', (tester) async {
    final state = await showHarness(tester, size: const Size(402, 874));
    Future<void> search(String value) async {
      await openQueryPanel(tester);
      final field = find.widgetWithText(TextField, '课程名称或作业标题');
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await closeQueryPanel(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
    }

    await search('A 课程');
    final detail = find.byType(AssignmentCard);
    await Scrollable.ensureVisible(tester.element(detail), alignment: .5);
    await tester.pumpAndSettle();
    expect(detail.hitTestable(), findsOneWidget);
    await tester.tap(detail);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await search('B 课程');
    final choice = find.byType(AssignmentCard);
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(state.queries.last.courseId, 'B');
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
  void progressive() => setState(() {
    snapshot = snapshot.copyWith(
      status: FeatureLoadStatus.loading,
      updatedAt: DateTime.utc(2026, 9, 22),
    );
  });
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
    initialDestination: UiDestination.coursework,
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

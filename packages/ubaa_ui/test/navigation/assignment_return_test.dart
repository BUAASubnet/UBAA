import '../support/home_shell_harness.dart';
import '../support/home_todos.dart';
import 'package:ubaa_ui/src/features/coursework/assignment_content.dart'
    show AssignmentCard;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart';
import 'package:ubaa_ui/src/common/read_navigator.dart';

void main() {
  testWidgets('首页直达研讨室订单后缓存失效，返回仍直接退出到首页', (tester) async {
    final key = GlobalKey<FeatureReadNavigatorState>();
    var exits = 0;
    Future<void> mountNavigator(int epoch) => tester.pumpWidget(
      MaterialApp(
        home: FeatureReadNavigator(
          key: key,
          snapshot: FeatureSnapshot(feature: FeatureId.cgyy),
          cacheEpoch: epoch,
          initialHomeTarget: const FeatureReadNavigation(
            feature: FeatureId.cgyy,
            query: FeatureQuery(view: FeatureQueryView.cgyyOrders),
          ),
          onExit: () => exits++,
          onRetry: () async {},
          onQuery: (_) async {},
          onVisibleSnapshot: (_, _) {},
          pageBuilder: (_) => const SizedBox(),
        ),
      ),
    );
    await mountNavigator(0);
    await mountNavigator(1);
    key.currentState!.goBack();
    await tester.pump();
    expect(exits, 1);
  });
  for (final feature in [FeatureId.spoc, FeatureId.judge]) {
    testWidgets('${feature.title}首页直达详情首帧无列表，返回首页后分类入口恢复列表', (tester) async {
      final state = await mount(tester, feature);
      await tester.tap(find.text('测试作业1'));
      await tester.pump();
      expect(find.byType(AssignmentCard), findsNothing, reason: '首页目标首帧不显示父列表');
      await tester.pumpAndSettle();
      expect(find.text('详情作业1'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '首页'), findsOneWidget);
      expect(state.queries, hasLength(1), reason: '返回首页不读取功能列表');
      await openFeature(tester, feature);
      expect(find.text('测试作业2'), findsOneWidget);
      await tester.tap(find.byType(AssignmentCard).first);
      await tester.pumpAndSettle();
      expect(find.text('详情作业1'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('测试作业2'), findsOneWidget, reason: '分类列表打开详情后返回父列表');
      await openFeature(tester, feature);
      expect(find.text('测试作业2'), findsOneWidget, reason: '功能卡入口始终打开列表');
    });
    testWidgets('${feature.title}只保留详情快照时功能入口恢复列表', (tester) async {
      final state = await mount(tester, feature, detailOnly: true);
      await openFeature(tester, feature);
      expect(find.text('测试作业2'), findsOneWidget);
      expect(state.queries.single.view, FeatureQueryView.summary);
    });
  }
}

Future<_HarnessState> mount(
  WidgetTester tester,
  FeatureId feature, {
  bool detailOnly = false,
}) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: _Harness(feature: feature, detailOnly: detailOnly),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<_HarnessState>(find.byType(_Harness));
}

class _Harness extends StatefulWidget {
  const _Harness({required this.feature, required this.detailOnly});
  final FeatureId feature;
  final bool detailOnly;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final queries = <FeatureQuery>[];
  int revision = 1;
  late FeatureSnapshot snapshot;
  FeatureQuery get detailQuery => FeatureQuery(
    view: widget.feature == FeatureId.spoc
        ? FeatureQueryView.spocDetail
        : FeatureQueryView.judgeDetail,
    courseId: widget.feature == FeatureId.judge ? '1' : null,
    assignmentId: '1',
  );
  @override
  void initState() {
    super.initState();
    snapshot = makeSnapshot(
      widget.detailOnly ? detailQuery : const FeatureQuery(),
    );
  }

  FeatureSnapshot makeSnapshot(FeatureQuery query) {
    final child = query.view != FeatureQueryView.summary;
    return FeatureSnapshot(
      feature: widget.feature,
      status: FeatureLoadStatus.success,
      readContext: FeatureReadContext(query: query, requestRevision: revision),
      details: [
        for (final id in child ? ['1'] : ['1', '2'])
          FeatureDetail(
            title: '${child ? '详情' : '测试'}作业$id',
            presentation: widget.feature == FeatureId.spoc
                ? SpocAssignmentPresentation(
                    courseId: '1',
                    courseName: '测试课程',
                    assignmentId: id,
                    dueTime: '2099-12-01 23:59:00',
                    status: AssignmentSubmissionStatus.unsubmitted,
                    statusText: '未提交',
                    isDetail: child,
                  )
                : JudgeAssignmentPresentation(
                    courseId: '1',
                    courseName: '测试课程',
                    assignmentId: id,
                    dueTime: '2099-12-01 23:59:00',
                    totalProblems: 1,
                    submittedCount: 0,
                    status: AssignmentSubmissionStatus.unsubmitted,
                    statusText: '未提交',
                    isDetail: child,
                  ),
            readNavigation: child
                ? null
                : FeatureReadNavigation(
                    feature: widget.feature,
                    query: detailQuery,
                  ),
          ),
      ],
    );
  }

  Future<void> query(FeatureId feature, FeatureQuery query) async {
    queries.add(query);
    setState(() {
      revision++;
      snapshot = makeSnapshot(query);
    });
  }

  @override
  Widget build(BuildContext context) => HomeShellHarness(
    project: homeTodoFixture,
    child: UbaaMainShell(
      user: const UserSummary(username: 'synthetic'),
      snapshots: {
        for (final feature in FeatureId.values)
          feature: feature == widget.feature
              ? snapshot
              : FeatureSnapshot(feature: feature),
      },
      routePolicy: RoutePolicy.auto,
      onRefresh: () async {},
      onRetryFeature: (feature) => query(feature, const FeatureQuery()),
      onFeatureQuery: query,
      onLogout: () async {},
      onLogoutAndClearAccount: () async {},
      onRoutePolicyChanged: (_) {},
    ),
  );
}

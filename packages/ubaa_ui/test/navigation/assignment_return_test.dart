import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart';

void main() {
  for (final feature in [FeatureId.spoc, FeatureId.judge]) {
    testWidgets('${feature.title}首页直达详情后返回列表，退出再进不复活详情', (tester) async {
      final state = await mount(tester, feature);
      await tester.tap(find.text('测试作业1'));
      await tester.pumpAndSettle();
      expect(find.text('详情作业1'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('测试作业2'), findsOneWidget);
      expect(state.queries, hasLength(1), reason: '返回复用父列表');
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await openFeature(tester, feature);
      expect(find.text('测试作业2'), findsOneWidget);
      await tester.tap(find.byTooltip('查看作业详情').first);
      await tester.pumpAndSettle();
      expect(find.text('详情作业1'), findsOneWidget);
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
  Widget build(BuildContext context) => UbaaMainShell(
    user: const UserSummary(username: 'synthetic'),
    snapshots: {
      for (final feature in FeatureId.values)
        feature: feature == widget.feature
            ? snapshot
            : FeatureSnapshot(feature: feature),
    },
    routePolicy: RoutePolicy.auto,
    telemetryEnabled: false,
    onRefresh: () async {},
    onRetryFeature: (feature) => query(feature, const FeatureQuery()),
    onFeatureQuery: query,
    onLogout: () async {},
    onLogoutAndClearAccount: () async {},
    onRoutePolicyChanged: (_) {},
    onTelemetryChanged: (_) {},
  );
}

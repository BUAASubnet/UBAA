import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('刷新当前查询使用已应用参数而不采用未应用草稿', (tester) async {
    final harness = await _show(tester);
    await tester.enterText(find.widgetWithText(TextField, '学期编码'), '未应用');
    await tester.tap(find.byTooltip('刷新当前查询'));
    await tester.pumpAndSettle();
    expect(harness.queries, hasLength(1));
    expect(harness.queries.single.view, FeatureQueryView.scheduleTerms);
    expect(harness.queries.single.term, isNull);
    expect(_fieldText(tester, '学期编码'), '未应用');
  });
  testWidgets('父页返回后无关epoch通知不会复活已退出子页', (tester) async {
    final harness = await _show(tester);
    await tester.enterText(find.widgetWithText(TextField, '筛选详情'), '秋季');
    await tester.tap(find.text('查看周次'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回上一层'));
    await tester.pumpAndSettle();
    harness.invalidate();
    await tester.pumpAndSettle();
    expect(find.text('秋季学期'), findsOneWidget);
    expect(find.text('第 7 周'), findsNothing);
    expect(_fieldText(tester, '筛选详情'), '秋季');
  });

  testWidgets('epoch先通知旧快照，随后不同query权威结果仍更新页面', (tester) async {
    final harness = await _show(tester);
    await tester.tap(find.text('查看周次'));
    await tester.pumpAndSettle();
    harness.invalidate();
    await tester.pumpAndSettle();
    harness.externalResult();
    await tester.pumpAndSettle();
    expect(find.text('权威更新后的结果'), findsOneWidget);
    expect(find.text('第 7 周'), findsNothing);
    expect(find.text('返回上一层'), findsNothing);
  });
  testWidgets('学期点选仅查一次，子页返回保留父搜索和查询草稿', (tester) async {
    final harness = await _show(tester);
    await tester.enterText(find.widgetWithText(TextField, '筛选详情'), '秋季');
    await tester.enterText(find.widgetWithText(TextField, '学期编码'), '未应用草稿');
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看周次'));
    await tester.pumpAndSettle();
    expect(harness.queries, hasLength(1));
    expect(harness.queries.single.term, 'term-real');
    expect(find.text('第 7 周'), findsOneWidget);
    expect(_fieldText(tester, '学期编码'), 'term-real');
    await tester.tap(find.text('返回上一层'));
    await tester.pumpAndSettle();
    expect(harness.queries, hasLength(1));
    expect(find.text('秋季学期'), findsOneWidget);
    expect(_fieldText(tester, '筛选详情'), '秋季');
    expect(_fieldText(tester, '学期编码'), '未应用草稿');
  });

  testWidgets('子查询未完成就返回，迟到结果不覆盖父列表', (tester) async {
    final harness = await _show(tester);
    harness.pending = Completer<void>();
    await tester.tap(find.text('查看周次'));
    await tester.pump();
    await tester.tap(find.text('返回上一层'));
    await tester.pump();
    harness.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('秋季学期'), findsOneWidget);
    expect(find.text('第 7 周'), findsNothing);
    expect(harness.queries, hasLength(1));
  });

  testWidgets('读取epoch改变后不能返回旧父缓存', (tester) async {
    final harness = await _show(tester);
    await tester.tap(find.text('查看周次'));
    await tester.pumpAndSettle();
    harness.invalidate();
    await tester.pumpAndSettle();
    expect(find.text('返回上一层'), findsNothing);
    expect(find.text('返回功能列表'), findsOneWidget);
    expect(harness.queries, hasLength(1));
  });
}

String _fieldText(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;

Future<_HarnessState> _show(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: _Harness()));
  await tester.pumpAndSettle();
  final card = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.widgetWithText(Card, FeatureId.schedule.title),
  );
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
  final queries = <FeatureQuery>[];
  Completer<void>? pending;
  int epoch = 0;
  FeatureSnapshot snapshot = FeatureSnapshot(
    feature: FeatureId.schedule,
    status: FeatureLoadStatus.success,
    readContext: FeatureReadContext(
      query: const FeatureQuery(view: FeatureQueryView.scheduleTerms),
      requestRevision: 1,
    ),
    details: const [
      FeatureDetail(
        title: '秋季学期',
        presentation: TermPresentation(
          code: 'term-real',
          selected: true,
          index: 1,
        ),
        fields: [FeatureField(label: '学期编码', value: '不可信展示编码')],
        readNavigation: FeatureReadNavigation(
          feature: FeatureId.schedule,
          query: FeatureQuery(
            view: FeatureQueryView.scheduleWeeks,
            term: 'term-real',
          ),
        ),
      ),
    ],
  );
  void invalidate() => setState(() => epoch++);
  void externalResult() => setState(
    () => snapshot = FeatureSnapshot(
      feature: FeatureId.schedule,
      status: FeatureLoadStatus.success,
      readContext: FeatureReadContext(
        query: const FeatureQuery(),
        requestRevision: 99,
      ),
      details: const [FeatureDetail(title: '权威更新后的结果')],
    ),
  );
  Future<void> query(FeatureId feature, FeatureQuery value) async {
    queries.add(value);
    setState(
      () => snapshot = FeatureSnapshot(
        feature: feature,
        status: FeatureLoadStatus.loading,
        readContext: FeatureReadContext(
          query: value,
          requestRevision: queries.length + 1,
        ),
      ),
    );
    await pending?.future;
    if (!mounted) return;
    setState(
      () => snapshot = FeatureSnapshot(
        feature: feature,
        status: FeatureLoadStatus.success,
        readContext: FeatureReadContext(
          query: value,
          requestRevision: queries.length + 1,
        ),
        details: const [
          FeatureDetail(
            title: '第 7 周',
            presentation: WeekPresentation(
              requestTerm: 'term-real',
              responseTerm: 'term-real',
              number: 7,
              current: false,
              startDate: '2026-09-07',
              endDate: '2026-09-13',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => UbaaMainShell(
    user: const UserSummary(username: 'fixture-student'),
    initialTab: 1,
    snapshots: {
      for (final feature in FeatureId.values)
        feature: feature == FeatureId.schedule
            ? snapshot
            : FeatureSnapshot(feature: feature),
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../support/navigation.dart';

void main() {
  testWidgets('缓存学期选项仍可选择并立即按学期查询考试', (tester) async {
    final queries = <FeatureQuery>[];
    await _show(
      tester,
      queries,
      (_) async => FeatureResult.success(
        evidence: DataEvidence(
          accountId: 'synthetic',
          origin: DataOrigin.persisted,
          fetchedAt: DateTime(2026, 9, 1, 8, 30),
          complete: true,
          savedForOffline: true,
        ),
        details: const [
          FeatureDetail(
            title: '合成旧学期',
            presentation: TermPresentation(code: 'a', selected: true, index: 1),
          ),
        ],
      ),
    );
    await tester.tap(find.text('当前学期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('合成旧学期'));
    await tester.pumpAndSettle();
    expect(queries.single.term, 'a');
    expect(queries.single.view, FeatureQueryView.summary);
  });

  testWidgets('少量学期的选择面板按内容收缩，不固定占半页', (tester) async {
    await _show(
      tester,
      [],
      (_) async => const FeatureResult.success(
        details: [
          FeatureDetail(
            title: '合成甲学期',
            presentation: TermPresentation(code: 'a', selected: true, index: 1),
          ),
          FeatureDetail(
            title: '合成乙学期',
            presentation: TermPresentation(
              code: 'b',
              selected: false,
              index: 2,
            ),
          ),
        ],
      ),
    );
    await tester.tap(find.text('当前学期'));
    await tester.pumpAndSettle();
    final surface = find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Material),
        )
        .first;
    expect(tester.getSize(surface).height, lessThan(400));
    expect(find.text('合成甲学期'), findsOneWidget);
    expect(find.text('合成乙学期'), findsOneWidget);
  });

  testWidgets('选项打开后读取epoch变化不能应用旧学期', (tester) async {
    final epoch = ValueNotifier(0);
    addTearDown(epoch.dispose);
    final queries = <FeatureQuery>[];
    await _show(
      tester,
      queries,
      (_) async => const FeatureResult.success(
        details: [
          FeatureDetail(
            title: '旧会话学期',
            presentation: TermPresentation(
              code: 'old-term',
              selected: false,
              index: 1,
            ),
          ),
        ],
      ),
      epoch: epoch,
    );
    await tester.tap(find.text('当前学期'));
    await tester.pumpAndSettle();
    epoch.value++;
    await tester.pumpAndSettle();
    await tester.tap(find.text('旧会话学期'));
    await tester.pumpAndSettle();
    expect(queries, isEmpty);
    expect(find.text('连接状态已变化，请重新选择学期。'), findsOneWidget);
  });

  testWidgets('考试学期按名称选择，只提交typed编码而非展示字段', (tester) async {
    final loads = <bool>[];
    final queries = <FeatureQuery>[];
    await _show(tester, queries, (force) async {
      loads.add(force);
      return const FeatureResult.success(
        details: [
          FeatureDetail(
            title: '2026秋季学期',
            fields: [FeatureField(label: '学期编码', value: '错误展示值')],
            presentation: TermPresentation(
              code: 'term-safe',
              selected: true,
              index: 1,
            ),
          ),
        ],
      );
    });

    expect(loads, isEmpty);
    await tester.tap(find.text('当前学期'));
    await tester.pumpAndSettle();
    expect(loads, [false]);
    await tester.tap(find.text('2026秋季学期'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(queries.single.term, 'term-safe');
  });

  testWidgets('学期选项失败可显式重试，且不提供手填学期编码', (tester) async {
    final loads = <bool>[];
    final queries = <FeatureQuery>[];
    await _show(tester, queries, (force) async {
      loads.add(force);
      return const FeatureResult.failure(
        UiError(
          code: UbaaErrorCode.networkError,
          title: '获取失败',
          message: '暂时无法获取学期',
          retryable: true,
        ),
      );
    });
    await tester.tap(find.text('当前学期'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法获取学期'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '重试'));
    await tester.pumpAndSettle();
    expect(loads, [false, true]);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('学期编码'), findsNothing);
    expect(queries, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

/// 学期只在考试筛选中提供；成绩由页面顶部切换器负责。
Future<void> _show(
  WidgetTester tester,
  List<FeatureQuery> queries,
  Future<FeatureResult> Function(bool) loader, {
  ValueNotifier<int>? epoch,
}) async {
  final revisions = epoch ?? ValueNotifier(0);
  if (epoch == null) addTearDown(revisions.dispose);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: ValueListenableBuilder<int>(
        valueListenable: revisions,
        builder: (_, revision, __) => UbaaMainShell(
          readCacheEpoch: revision,
          initialDestination: UiDestination.academic,
          user: const UserSummary(username: 'fixture-student'),
          snapshots: {
            for (final id in FeatureId.values)
              id: FeatureSnapshot(
                feature: id,
                status: FeatureLoadStatus.success,
                details: const [FeatureDetail(title: '合成结果')],
              ),
          },
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onLoadAcademicTerms: loader,
          onFeatureQuery: (_, query) async => queries.add(query),
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final grid = find.byType(CustomScrollView);
  final card = find.descendant(
    of: grid,
    matching: find.widgetWithText(Card, FeatureId.exam.title),
  );
  await tester.scrollUntilVisible(
    card,
    200,
    scrollable: find.descendant(of: grid, matching: find.byType(Scrollable)),
  );
  await tester.tap(card);
  await tester.pumpAndSettle();
  await openQueryPanel(tester);
}

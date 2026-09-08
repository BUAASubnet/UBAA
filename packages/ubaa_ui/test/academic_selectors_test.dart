import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'support/navigation.dart';

void main() {
  testWidgets('少量学期的选择面板按内容收缩，不固定占半页', (tester) async {
    await _show(
      tester,
      FeatureId.grades,
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
    await tester.tap(find.text('选择学期'));
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
  testWidgets('今日查询不携带旧周次草稿，按输入查询保留兼容周表', (tester) async {
    final queries = <FeatureQuery>[];
    await _show(
      tester,
      FeatureId.schedule,
      queries,
      (_) async => const FeatureResult.empty(),
    );
    await _chooseView(tester, '周课表');
    await tester.enterText(find.widgetWithText(TextField, '学期编码'), 'term-week');
    await tester.enterText(find.widgetWithText(TextField, '周次'), '3');
    await _chooseView(tester, '今日课程');
    expect(find.widgetWithText(TextField, '学期编码'), findsNothing);
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(queries.single.view, FeatureQueryView.scheduleToday);
    expect(queries.single.term, isNull);
    expect(queries.single.week, isNull);
    await _chooseView(tester, '按输入查询');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(queries.last.view, FeatureQueryView.summary);
    expect(queries.last.term, 'term-week');
    expect(queries.last.week, 3);
  });
  testWidgets('选项打开后读取epoch变化不能应用旧学期', (tester) async {
    final epoch = ValueNotifier(0);
    addTearDown(epoch.dispose);
    await _show(
      tester,
      FeatureId.grades,
      [],
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
    await tester.tap(find.text('选择学期'));
    await tester.pumpAndSettle();
    epoch.value++;
    await tester.pumpAndSettle();
    await tester.tap(find.text('旧会话学期'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '学期编码'))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text('连接状态已变化，请重新选择学期。'), findsOneWidget);
  });
  testWidgets('教室中文日期选择仅回填，应用时仍传严格日期', (tester) async {
    final queries = <FeatureQuery>[];
    await _show(
      tester,
      FeatureId.classroom,
      queries,
      (_) async => const FeatureResult.empty(),
    );
    await tester.enterText(find.widgetWithText(TextField, '日期'), '2026-09-08');
    await tester.tap(find.byTooltip('选择日期'));
    await tester.pumpAndSettle();
    expect(find.text('选择查询日期'), findsOneWidget);
    await tester.tap(find.text('9').last);
    await tester.tap(find.text('使用此日期'));
    await tester.pumpAndSettle();
    expect(queries, isEmpty);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '日期'))
          .controller!
          .text,
      '2026-09-09',
    );
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(queries.single.date, DateTime(2026, 9, 9));
  });
  for (final feature in [
    FeatureId.schedule,
    FeatureId.exam,
    FeatureId.grades,
  ]) {
    testWidgets('${feature.title}学期选择只填typed编码，应用前不查询', (tester) async {
      final loads = <bool>[];
      final queries = <FeatureQuery>[];
      await _show(tester, feature, queries, (force) async {
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
      if (feature == FeatureId.schedule) {
        await tester.tap(find.byType(DropdownButton<FeatureQueryView>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('周课表').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, '周次'), '3');
      }
      expect(loads, isEmpty);
      await tester.tap(find.text('选择学期'));
      await tester.pumpAndSettle();
      expect(loads, [false]);
      await tester.tap(find.text('2026秋季学期'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '学期编码'))
            .controller!
            .text,
        'term-safe',
      );
      expect(queries, isEmpty);
      await tester.tap(find.text('应用筛选'));
      await tester.pumpAndSettle();
      expect(queries, hasLength(1));
      expect(queries.single.term, 'term-safe');
    });
  }

  testWidgets('学期选项失败可显式重试且手填入口保留', (tester) async {
    final loads = <bool>[];
    await _show(tester, FeatureId.grades, [], (force) async {
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
    await tester.tap(find.text('选择学期'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法获取学期'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '重试'));
    await tester.pumpAndSettle();
    expect(loads, [false, true]);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '学期编码'),
      'manual-term',
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _chooseView(WidgetTester tester, String text) async {
  await tester.tap(find.byType(DropdownButton<FeatureQueryView>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> _show(
  WidgetTester tester,
  FeatureId feature,
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
          initialTab: 1,
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
    matching: find.widgetWithText(Card, feature.title),
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart';

void main() {
  testWidgets('同一Shell更换账号清除已访问页面草稿和已应用查询', (tester) async {
    final queries = <FeatureQuery>[];
    await _mount(tester, queries);
    final shellState = tester.state(find.byType(UbaaMainShell));
    await _open(tester, FeatureId.exam);
    await tester.enterText(_field('学期编码'), '2026-2027-1');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('筛选详情'), '旧账号草稿');
    await _mount(tester, queries, username: 'another-fixture-student');
    expect(tester.state(find.byType(UbaaMainShell)), same(shellState));
    expect(find.byTooltip('返回'), findsNothing);
    await _open(tester, FeatureId.exam);
    expect(_view(tester), FeatureQueryView.summary);
    expect(_text(tester, '学期编码'), isEmpty);
    expect(_text(tester, '筛选详情'), isEmpty);
    expect(queries, hasLength(1));
  });

  testWidgets('同一成绩页跨断点保留本地搜索和滚动且不发查询', (tester) async {
    final queries = <FeatureQuery>[];
    await _mount(tester, queries, width: 799);
    await _open(tester, FeatureId.grades);
    await tester.enterText(_field('筛选详情'), '保留课程');
    await tester.pumpAndSettle();
    await closeQueryPanel(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();
    final offset = _listOffset(tester);
    expect(offset, greaterThan(0));
    final shellState = tester.state(find.byType(UbaaMainShell));

    for (final width in <double>[801, 599, 600, 1000]) {
      tester.view.physicalSize = Size(width, 1000);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(UbaaMainShell)), same(shellState));
      expect(find.byTooltip('返回'), findsOneWidget);
      expect(find.text(FeatureId.grades.title), findsOneWidget);
      expect(await queryFieldText(tester, '筛选详情'), '保留课程');
      expect(_listOffset(tester), closeTo(offset, 1));
      expect(queries, isEmpty);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('未应用的学期草稿返回后重入仍保留且不触发查询', (tester) async {
    final queries = <FeatureQuery>[];
    await _mount(tester, queries);
    await _open(tester, FeatureId.exam);
    await tester.enterText(_field('学期编码'), '2026-2027-1');
    await _back(tester);
    await _open(tester, FeatureId.exam);

    expect(_view(tester), FeatureQueryView.summary);
    expect(_text(tester, '学期编码'), '2026-2027-1');
    expect(queries, isEmpty);
  });

  testWidgets('重入保留未应用草稿而失败后的重试仍使用已应用查询', (tester) async {
    final queries = <FeatureQuery>[];
    // 已有缓存但刷新失败是公开 stale 状态，页面提供真实的“重试”入口。
    await _mount(tester, queries, staleExam: true);
    await _open(tester, FeatureId.exam);
    await tester.enterText(_field('学期编码'), '2026-2027-1');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(queries, hasLength(1));
    expect(queries.single.view, FeatureQueryView.summary);
    expect(queries.single.term, '2026-2027-1');

    await tester.enterText(_field('学期编码'), '2027-2028-2');
    await _back(tester);
    await _open(tester, FeatureId.exam);
    expect(_view(tester), FeatureQueryView.summary);
    expect(_text(tester, '学期编码'), '2027-2028-2');
    expect(queries, hasLength(1));

    await closeQueryPanel(tester);
    await tester.tap(find.widgetWithText(TextButton, '重试'));
    await tester.pumpAndSettle();
    expect(queries, hasLength(2));
    expect(queries.last.view, FeatureQueryView.summary);
    expect(queries.last.term, '2026-2027-1');
    expect(await queryFieldText(tester, '学期编码'), '2027-2028-2');
  });

  testWidgets('不同领域的未应用草稿隔离且各自重入恢复', (tester) async {
    final queries = <FeatureQuery>[];
    await _mount(tester, queries);
    await _open(tester, FeatureId.exam);
    await tester.enterText(_field('学期编码'), '2026-2027-1');
    await _back(tester);
    await _open(tester, FeatureId.grades);
    expect(_text(tester, '学期编码'), isEmpty);
    expect(_view(tester), FeatureQueryView.summary);
    await tester.enterText(_field('学期编码'), '2025-2026-2');
    await _back(tester);
    await _open(tester, FeatureId.exam);
    expect(_text(tester, '学期编码'), '2026-2027-1');
    expect(_view(tester), FeatureQueryView.summary);
    await _back(tester);
    await _open(tester, FeatureId.grades);
    expect(_text(tester, '学期编码'), '2025-2026-2');
    expect(_view(tester), FeatureQueryView.summary);
    expect(queries, isEmpty);
  });
}

Future<void> _mount(
  WidgetTester tester,
  List<FeatureQuery> queries, {
  double width = 799,
  bool staleExam = false,
  String username = 'fixture-student',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: UbaaMainShell(
        user: UserSummary(username: username),
        initialDestination: UiDestination.academic,
        snapshots: <FeatureId, FeatureSnapshot>{
          for (final feature in FeatureId.values)
            feature: FeatureSnapshot(
              feature: feature,
              status: staleExam && feature == FeatureId.exam
                  ? FeatureLoadStatus.stale
                  : FeatureLoadStatus.success,
              summary: '合成查询结果',
              details: <FeatureDetail>[
                for (var i = 0; i < 20; i++)
                  FeatureDetail(
                    title: '保留课程 $i',
                    fields: const <FeatureField>[
                      FeatureField(label: '成绩', value: '85'),
                    ],
                  ),
                const FeatureDetail(title: '另一课程'),
              ],
            ),
        },
        routePolicy: RoutePolicy.auto,
        telemetryEnabled: false,
        onRefresh: () async => fail('状态连续性操作不得全局刷新'),
        onRetryFeature: (_) async => fail('已应用查询不得回退默认刷新'),
        onFeatureQuery: (_, query) async => queries.add(query),
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextField, label);
String _text(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;
FeatureQueryView? _view(WidgetTester tester) => tester
    .widget<DropdownButton<FeatureQueryView>>(
      find.byType(DropdownButton<FeatureQueryView>),
    )
    .value;

double _listOffset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.descendant(
          of: find.byKey(const ValueKey<String>('feature-pages')),
          matching: find.byType(ListView),
        ),
        matching: find.byType(Scrollable),
      ),
    )
    .position
    .pixels;

Future<void> _open(WidgetTester tester, FeatureId feature) async {
  await openFeature(tester, feature);
  await openQueryPanel(tester);
}

Future<void> _back(WidgetTester tester) async {
  await closeQueryPanel(tester);
  await tester.tap(find.byTooltip('返回'));
  await tester.pumpAndSettle();
}

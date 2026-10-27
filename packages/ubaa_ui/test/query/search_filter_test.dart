import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart';

const _searchField = ValueKey<String>('feature-search-field');
const _filterButton = ValueKey<String>('feature-filter-button');

Future<List<FeatureQuery>> _pumpShell(WidgetTester tester) async {
  final queries = <FeatureQuery>[];
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: UbaaMainShell(
        user: const UserSummary(username: 'fixture-student'),
        snapshots: {
          for (final id in FeatureId.values)
            id: FeatureSnapshot(
              feature: id,
              status: FeatureLoadStatus.success,
              details: const [FeatureDetail(title: '保留的课程结果')],
            ),
        },
        routePolicy: RoutePolicy.auto,
        telemetryEnabled: false,
        onFeatureQuery: (_, query) async => queries.add(query),
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
  return queries;
}

void main() {
  testWidgets('搜索关键字在失焦后仍显示在列表上方，并可一键清除', (tester) async {
    await _pumpShell(tester);
    await openFeature(tester, FeatureId.grades);
    expect(find.text('保留的课程结果'), findsOneWidget);

    await tester.enterText(find.byKey(_searchField), 'zzz');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('保留的课程结果'), findsNothing);
    expect(
      find.descendant(of: find.byKey(_searchField), matching: find.text('zzz')),
      findsOneWidget,
      reason: '生效中的关键字必须始终可见',
    );

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('保留的课程结果'), findsOneWidget);
    expect(find.byTooltip('清除搜索'), findsNothing);
  });

  testWidgets('考试状态筛选点选即生效，不暴露开发参数或二次确认', (tester) async {
    final queries = await _pumpShell(tester);
    await openFeature(tester, FeatureId.exam);
    await tester.tap(find.byKey(_filterButton));
    await tester.pumpAndSettle();

    for (final text in ['应用筛选', '学期编码', '周次', '筛选详情', '完成']) {
      expect(find.text(text), findsNothing, reason: '筛选面板不应包含“$text”');
    }
    await tester.tap(find.widgetWithText(ChoiceChip, '已安排'));
    await tester.pumpAndSettle();
    expect(queries.single.view, FeatureQueryView.examArranged);
    expect(
      find.descendant(of: find.byKey(_filterButton), matching: find.text('1')),
      findsOneWidget,
      reason: '筛选按钮显示生效条件数量',
    );
  });

  testWidgets('菜单页不提供搜索，博雅列表筛选不含视图切换和课程 ID', (tester) async {
    await _pumpShell(tester);
    await tester.tap(
      find
          .byType(NavigationDestination)
          .at(UiDestination.forFeature(FeatureId.bykc).index),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Card, FeatureId.bykc.title));
    await tester.pumpAndSettle();
    expect(find.byKey(_searchField), findsNothing);
    expect(find.byKey(_filterButton), findsNothing);
    expect(find.byIcon(Icons.search), findsNothing);

    await tester.tap(find.widgetWithText(Card, '选择课程'));
    await tester.pumpAndSettle();
    expect(find.byKey(_searchField), findsOneWidget);
    await tester.tap(find.byKey(_filterButton));
    await tester.pumpAndSettle();
    for (final text in ['课程 ID', '课程列表', '课程详情', '应用筛选', '完成']) {
      expect(find.text(text), findsNothing, reason: '筛选面板不应包含“$text”');
    }
    await tester.tap(find.widgetWithText(FilterChip, '已过期'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '已过期'))
          .selected,
      isTrue,
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('已打开详情切换主题后标题颜色与当前主题一致', (tester) async {
    _viewport(tester, const Size(834, 1210));
    final state = ValueNotifier<FeatureSnapshot>(_grades());
    addTearDown(state.dispose);
    await _mount(tester, state);
    await _open(tester, FeatureId.grades);
    final shell = tester.state(find.byType(UbaaMainShell));
    await _mount(tester, state, themeMode: ThemeMode.dark);
    expect(tester.state(find.byType(UbaaMainShell)), same(shell));
    final title = find.text('保留课程 0');
    final theme = Theme.of(tester.element(title));
    expect(theme.brightness, Brightness.dark);
    expect(
      tester.widget<Text>(title).style?.color,
      theme.textTheme.titleMedium?.color,
    );
  });

  for (final next in [FeatureLoadStatus.success, FeatureLoadStatus.stale]) {
    testWidgets('详情刷新经过加载后保留本地搜索和滚动：${next.name}', (tester) async {
      _viewport(tester, const Size(799, 1000));
      final state = ValueNotifier<FeatureSnapshot>(_grades());
      addTearDown(state.dispose);
      await _mount(tester, state);
      await _open(tester, FeatureId.grades);
      await tester.enterText(_search, '保留课程');
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -280));
      await tester.pumpAndSettle();
      final before = _offset(tester);
      expect(before, greaterThan(0));

      state.value = state.value.copyWith(status: FeatureLoadStatus.loading);
      await tester.pump(const Duration(milliseconds: 100));
      state.value = state.value.copyWith(status: next);
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(_search).controller!.text, '保留课程');
      expect(_offset(tester), closeTo(before, 1));
      expect(find.text('不匹配的课程'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('明确空结果清除旧条目但再次有结果时保留本地搜索', (tester) async {
    _viewport(tester, const Size(799, 1000));
    final state = ValueNotifier<FeatureSnapshot>(_grades());
    addTearDown(state.dispose);
    await _mount(tester, state);
    await _open(tester, FeatureId.grades);
    await tester.enterText(_search, '保留课程');
    await tester.pumpAndSettle();
    state.value = const FeatureSnapshot(
      feature: FeatureId.grades,
      status: FeatureLoadStatus.empty,
    );
    await tester.pumpAndSettle();
    expect(find.text('保留课程 0'), findsNothing);
    expect(find.text('暂无成绩查询数据'), findsOneWidget);
    state.value = _grades();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_search).controller!.text, '保留课程');
    expect(find.text('不匹配的课程'), findsNothing);
  });

  testWidgets('横向手机键盘占位时侧栏末项可滚动访问', (tester) async {
    _viewport(tester, const Size(844, 390));
    final state = ValueNotifier<FeatureSnapshot>(_grades());
    addTearDown(state.dispose);
    await _mount(tester, state);
    tester.view.viewInsets = const FakeViewPadding(bottom: 120);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final profile = find.byIcon(Icons.person_outline);
    await tester.ensureVisible(profile);
    await tester.pumpAndSettle();
    expect(profile.hitTestable(), findsOneWidget);
    await tester.tap(profile);
    await tester.pumpAndSettle();
    expect(find.text('外观主题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final feature in [FeatureId.cgyy, FeatureId.libbook]) {
    testWidgets('手机放大文字和键盘占位时${feature.title}可滚动到应用且只查询一次', (tester) async {
      // 这是布局行为证据；真实软键盘另由原生宿主验收。
      _viewport(tester, const Size(360, 800));
      final state = ValueNotifier<FeatureSnapshot>(_grades());
      addTearDown(state.dispose);
      final queries = <FeatureQuery>[];
      await _mount(tester, state, scale: 1.3, queries: queries, initialTab: 2);
      await _open(tester, feature);
      await tester.tap(find.byType(DropdownButton<FeatureQueryView>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(feature == FeatureId.cgyy ? '日期空间' : '座位查询').last,
      );
      await tester.pumpAndSettle();
      if (feature == FeatureId.cgyy) {
        await tester.enterText(find.widgetWithText(TextField, '站点 ID'), '3');
      } else {
        await tester.enterText(
          find.widgetWithText(TextField, '分区 ID'),
          'fixture-area',
        );
        await tester.enterText(
          find.widgetWithText(TextField, '时段编号（必填）'),
          'slot-1',
        );
      }
      await tester.enterText(
        find.widgetWithText(TextField, '日期'),
        '2026-09-08',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final apply = find.text('应用筛选');
      await tester.ensureVisible(apply);
      await tester.pumpAndSettle();
      expect(apply.hitTestable(), findsOneWidget);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(queries, hasLength(1));
      if (feature == FeatureId.cgyy) {
        expect(queries.single.view, FeatureQueryView.cgyyDayInfo);
        expect(queries.single.siteId, 3);
      } else {
        expect(queries.single.view, FeatureQueryView.libbookSeats);
        expect(queries.single.areaId, 'fixture-area');
        expect(queries.single.segment, 'slot-1');
      }
      expect(queries.single.date, DateTime(2026, 9, 8));
      expect(tester.takeException(), isNull);
    });
  }
}

FeatureSnapshot _grades() => FeatureSnapshot(
  feature: FeatureId.grades,
  status: FeatureLoadStatus.success,
  summary: '合成成绩',
  details: [
    for (var i = 0; i < 20; i++)
      FeatureDetail(
        title: '保留课程 $i',
        fields: const [FeatureField(label: '成绩', value: '85')],
      ),
    const FeatureDetail(title: '不匹配的课程'),
  ],
);

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

Future<void> _mount(
  WidgetTester tester,
  ValueNotifier<FeatureSnapshot> state, {
  double scale = 1,
  List<FeatureQuery>? queries,
  int initialTab = 1,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      darkTheme: UbaaTheme.dark(),
      themeMode: themeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: ValueListenableBuilder<FeatureSnapshot>(
        valueListenable: state,
        builder: (context, value, _) => UbaaMainShell(
          user: const UserSummary(username: 'fixture-student'),
          initialTab: initialTab,
          snapshots: {
            for (final feature in FeatureId.values)
              feature: feature == FeatureId.grades
                  ? value
                  : FeatureSnapshot(
                      feature: feature,
                      status: FeatureLoadStatus.success,
                      resolvedRoute: ConnectionMode.direct,
                      details: const [FeatureDetail(title: '合成条目')],
                    ),
          },
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async => fail('本地状态操作不得全量刷新'),
          onRetryFeature: (_) async => fail('本地状态操作不得默认刷新'),
          onFeatureQuery: (_, query) async {
            if (queries == null) fail('刷新展示状态不得自行查询');
            queries.add(query);
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _search => find.widgetWithText(TextField, '筛选详情');
double _offset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    )
    .position
    .pixels;

Future<void> _open(WidgetTester tester, FeatureId feature) async {
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
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
}

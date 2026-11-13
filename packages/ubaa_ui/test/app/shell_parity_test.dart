import '../support/home_shell_harness.dart';
import '../support/home_todos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/app/home.dart' show HomeView;
import 'package:ubaa_ui/src/features/agenda/view.dart';

void main() {
  for (final inset in [24.0, 34.0, 48.0]) {
    testWidgets('底栏完整避开 $inset 像素系统导航区', (tester) async {
      tester.view.padding = FakeViewPadding(bottom: inset);
      tester.view.viewPadding = FakeViewPadding(bottom: inset);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await mount(tester);
      final bar = find.byType(NavigationBar);
      final safeBottom = 874 - inset;
      for (final destination in find.byType(NavigationDestination).evaluate()) {
        expect(
          tester.getRect(find.byWidget(destination.widget)).bottom,
          lessThanOrEqualTo(safeBottom),
        );
      }
      expect(tester.getSize(bar).height, 56 + inset);
    });
  }
  // Home 指示条只占屏幕底部约 13 像素，底栏不必让出整个 34 像素安全区。
  testWidgets(
    'iOS 底栏避开 Home 指示条但不让出整个安全区',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await mount(tester);
      for (final destination in find.byType(NavigationDestination).evaluate()) {
        expect(
          tester.getRect(find.byWidget(destination.widget)).bottom,
          lessThanOrEqualTo(874 - 20),
        );
      }
      expect(tester.getSize(find.byType(NavigationBar)).height, 56 + 20);
    },
  );
  testWidgets('已登录但日程服务未启用时提示存储条件并禁用新建', (tester) async {
    await mount(tester, tab: UiDestination.agenda);
    expect(find.text('日程暂不可用，请检查设备安全存储是否已启用'), findsOneWidget);
    expect(
      tester
          .widget<FloatingActionButton>(
            find.byKey(const ValueKey('agenda-create')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('功能页点另一底栏后内容与选中项一致，滑动从该页切到日程', (tester) async {
    await mount(tester, tab: UiDestination.study);
    await openGrade(tester);
    await tester.tap(
      find.byType(NavigationDestination).at(UiDestination.campus.index),
    );
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(Card, FeatureId.cgyy.title).hitTestable(),
      findsOneWidget,
    );
    await tester.drag(find.byType(PageView), const Offset(350, 0));
    await tester.pumpAndSettle();
    expect(
      find
          .descendant(of: find.byType(AgendaView), matching: find.text('日程'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      UiDestination.agenda.index,
    );
    // 日程页内左右滑动切换日期，回学习页改点底栏。
    await tester.tap(
      find.byType(NavigationDestination).at(UiDestination.study.index),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '学习'), findsOneWidget);
    expect(
      find.widgetWithText(Card, FeatureId.grades.title).hitTestable(),
      findsOneWidget,
    );
  });
  testWidgets('从独立设置页回到底栏，宽窄切换后仍显示所选分组', (tester) async {
    await mount(tester, tab: UiDestination.settings);
    await tester.tap(
      find.byType(NavigationDestination).at(UiDestination.campus.index),
    );
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(Card, FeatureId.cgyy.title).hitTestable(),
      findsOneWidget,
    );
    tester.view.physicalSize = const Size(1000, 874);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '学习'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(402, 874);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(Card, FeatureId.grades.title).hitTestable(),
      findsOneWidget,
    );
  });
  testWidgets('滑出首页保留 State 并停用可见性与 Ticker，滑回恢复', (tester) async {
    await mount(tester);
    final home = find.byType(HomeView, skipOffstage: false);
    final state = tester.state(home);
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '学习'), findsOneWidget);
    expect(tester.state(home), same(state));
    expect(tester.widget<HomeView>(home).visible, isFalse);
    expect(TickerMode.of(tester.element(home)), isFalse);
    await tester.drag(find.byType(PageView), const Offset(350, 0));
    await tester.pumpAndSettle();
    expect(tester.state(home), same(state));
    expect(tester.widget<HomeView>(home).visible, isTrue);
    expect(TickerMode.of(tester.element(home)), isTrue);
  });
  testWidgets('写入期间底栏与滑动均保留当前分组', (tester) async {
    await mount(
      tester,
      tab: UiDestination.study,
      writeState: WriteState(
        phase: WritePhase.committing,
        intent: WriteIntent(
          intentId: 'synthetic',
          operation: WriteOperation.bykcSelectCourse,
          targetSummary: '合成课程',
          resolvedRoute: ConnectionMode.direct,
          warnings: const [],
          expiresAt: DateTime(2099),
          requestDigest: 'synthetic',
        ),
      ),
    );
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(NavigationDestination).at(UiDestination.campus.index),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '学习'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      UiDestination.study.index,
    );
  });
  testWidgets('换账号清除页面状态后，底栏与分页仍保持同一分组', (tester) async {
    await mount(tester);
    await tester.tap(
      find.byType(NavigationDestination).at(UiDestination.campus.index),
    );
    await tester.pumpAndSettle();
    await mount(tester, username: 'second-synthetic');
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      UiDestination.campus.index,
    );
    expect(
      find.widgetWithText(Card, FeatureId.cgyy.title).hitTestable(),
      findsOneWidget,
    );
  });
  testWidgets('短错误说明按内容收缩并保留重试操作', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FriendlyErrorCard(
              error: const UiError(
                code: UbaaErrorCode.networkError,
                title: '网络不可用',
                message: '请检查网络后重试',
                retryable: true,
              ),
              onRetry: () => retried = true,
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(FriendlyErrorCard)).height,
      lessThan(
        tester.view.physicalSize.height / tester.view.devicePixelRatio / 2,
      ),
    );
    await tester.tap(find.text('重试'));
    expect(retried, isTrue);
  });
  testWidgets('系统返回沿当前领域父层回到分组', (tester) async {
    await mount(tester, tab: UiDestination.study);
    await openGrade(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '学习'), findsOneWidget);
    expect(find.byTooltip('返回'), findsNothing);
  });
  testWidgets('主分组切换进入校园后可打开研讨室并返回', (tester) async {
    await mount(tester);
    await tester.tap(find.text('校园'));
    await tester.pumpAndSettle();
    final entry = find.widgetWithText(Card, FeatureId.cgyy.title);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, FeatureId.cgyy.title), findsOneWidget);
    expect(find.text('我的预约'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '校园'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('手机底栏展示五项入口和首页标题', (tester) async {
    await mount(tester);
    expect(
      tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((item) => item.label),
      ['首页', '学习', '日程', '校园', '我的'],
    );
    expect(find.widgetWithText(AppBar, '首页'), findsOneWidget);
  });
  testWidgets('首页保留今日课表与待办状态', (tester) async {
    await mount(tester);
    expect(find.text('今日课表'), findsOneWidget);
    expect(find.text('待办'), findsOneWidget);
  });
  testWidgets('手机功能页保留全局底栏与父层返回', (tester) async {
    await mount(tester, tab: UiDestination.study);
    await openGrade(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.text('返回功能列表'), findsNothing);
    expect(find.text('返回上一层'), findsNothing);
  });
  testWidgets('设置页点选连接模式立即生效，当前模式不重复保存', (tester) async {
    final changed = <RoutePolicy>[];
    await mount(
      tester,
      tab: UiDestination.settings,
      onRoutePolicyChanged: changed.add,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('route-policy-auto')));
    await tester.tap(find.byKey(const ValueKey('route-policy-auto')));
    await tester.pumpAndSettle();
    expect(changed, isEmpty);
    await tester.ensureVisible(
      find.byKey(const ValueKey('route-policy-webvpn')),
    );
    await tester.tap(find.byKey(const ValueKey('route-policy-webvpn')));
    await tester.pumpAndSettle();
    expect(changed, [RoutePolicy.webvpn]);
  });
  testWidgets('少量查询条件按内容展开而不固定占据大半屏', (tester) async {
    await mount(tester, tab: UiDestination.study);
    await openGrade(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('feature-filter-button')),
    );
    await tester.pumpAndSettle();
    final panel = find.byWidgetPredicate(
      (widget) => widget is Material && widget.elevation == 8,
    );
    expect(tester.getSize(panel).height, lessThan(400));
  });
  test('研讨室预约使用旧版业务名称', () {
    expect(FeatureId.cgyy.title, '研讨室预约');
    expect(WriteOperation.cgyySubmitReservation.title, '研讨室预约');
  });
}

Future<void> openGrade(WidgetTester tester) async {
  final card = find.widgetWithText(Card, FeatureId.grades.title);
  await tester.ensureVisible(card);
  await tester.tap(card);
  await tester.pumpAndSettle();
}

Future<void> mount(
  WidgetTester tester, {
  UiDestination tab = UiDestination.home,
  String username = 'synthetic',
  WriteState writeState = const WriteState.idle(),
  List<FeatureQuery>? queries,
  ValueChanged<RoutePolicy>? onRoutePolicyChanged,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(402, 874);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: HomeShellHarness(
        project: homeTodoFixture,
        child: UbaaMainShell(
          user: UserSummary(username: username),
          initialDestination: tab,
          writeState: writeState,
          snapshots: {
            for (final id in FeatureId.values)
              id: FeatureSnapshot(
                feature: id,
                status: FeatureLoadStatus.success,
                resolvedRoute: ConnectionMode.direct,
                details: [FeatureDetail(title: '合成${id.title}')],
              ),
          },
          routePolicy: RoutePolicy.auto,
          activeRoutes: const [ConnectionMode.direct],
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (_, query) async {
            queries?.add(query);
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: onRoutePolicyChanged ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

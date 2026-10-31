import '../support/home_todos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/app/home.dart' show HomeView;

void main() {
  testWidgets('功能页点另一底栏后内容与选中项一致，滑动继续沿该页切换', (tester) async {
    await mount(tester, tab: UiDestination.academic);
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
    expect(find.widgetWithText(AppBar, '学业'), findsOneWidget);
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
    await tester.tap(find.widgetWithText(ListTile, '学业'));
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
    expect(find.widgetWithText(AppBar, '课程'), findsOneWidget);
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
      tab: UiDestination.coursework,
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
    expect(find.widgetWithText(AppBar, '课程'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      UiDestination.coursework.index,
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
    await mount(tester, tab: UiDestination.academic);
    await openGrade(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '学业'), findsOneWidget);
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
    expect(find.text('预约研讨室'), findsOneWidget);
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
      ['首页', '课程', '学业', '校园', '我的'],
    );
    expect(find.widgetWithText(AppBar, '首页'), findsOneWidget);
  });
  testWidgets('首页保留今日课表与待办状态', (tester) async {
    await mount(tester);
    expect(find.text('今日课表'), findsOneWidget);
    expect(find.text('待办区'), findsOneWidget);
  });
  testWidgets('手机功能页保留全局底栏与父层返回', (tester) async {
    await mount(tester, tab: UiDestination.academic);
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
    await mount(tester, tab: UiDestination.academic);
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
      home: UbaaMainShell(
        onProjectHomeTodos: homeTodoFixture,
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
        telemetryEnabled: false,
        activeRoutes: const [ConnectionMode.direct],
        onRefresh: () async {},
        onRetryFeature: (_) async {},
        onFeatureQuery: (_, query) async {
          queries?.add(query);
        },
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: onRoutePolicyChanged ?? (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

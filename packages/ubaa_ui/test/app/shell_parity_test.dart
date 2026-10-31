import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
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
  testWidgets('主分组切换进入校园服务后可打开研讨室并返回', (tester) async {
    await mount(tester);
    await tester.tap(find.text('校园服务'));
    await tester.pumpAndSettle();
    final entry = find.widgetWithText(Card, FeatureId.cgyy.title);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.text('预约研讨室'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '校园服务'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('手机底栏展示五项入口和首页标题', (tester) async {
    await mount(tester);
    expect(
      tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((item) => item.label),
      ['首页', '学业', '课程与作业', '校园服务', '我的'],
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
        user: const UserSummary(username: 'synthetic'),
        initialDestination: tab,
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

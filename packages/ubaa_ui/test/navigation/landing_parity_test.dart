import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../support/navigation.dart' show openQueryPanel;

void main() {
  testWidgets('默认子页保留首次错误，不因打开菜单项而自动重试', (tester) async {
    final state = await _open(tester, FeatureId.libbook);
    state.fail();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Card, '预约座位'));
    await tester.pumpAndSettle();
    expect(state.queries, isEmpty);
    expect(find.text('网络不可用'), findsOneWidget);
  });
  testWidgets('默认子页复用对应预载快照而显式应用仍发起读取', (tester) async {
    final state = await _open(tester, FeatureId.bykc);
    await tester.tap(find.widgetWithText(Card, '选择课程'));
    await tester.pumpAndSettle();
    expect(state.queries, isEmpty);
    expect(find.text('合成预载结果'), findsOneWidget);
    expect(find.widgetWithText(AppBar, '选择课程'), findsOneWidget);
    expect(find.byTooltip('实际路线：直连'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await openQueryPanel(tester);
    await tester.tap(find.widgetWithText(FilledButton, '应用筛选'));
    await tester.pumpAndSettle();
    expect(state.queries, hasLength(1));
    expect(find.byTooltip('实际路线：WebVPN'), findsOneWidget);
  });
  for (final entry in <FeatureId, List<String>>{
    FeatureId.bykc: ['选择课程', '我的课程', '课程统计'],
    FeatureId.libbook: ['预约座位', '我的预约'],
    FeatureId.cgyy: ['预约研讨室', '我的预约', '查看密码'],
  }.entries) {
    testWidgets('${entry.key.title}沿旧版先显示子菜单', (tester) async {
      final state = await _open(tester, entry.key);
      for (final title in entry.value) {
        expect(find.widgetWithText(Card, title), findsOneWidget);
      }
      expect(find.text('合成预载结果'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byTooltip('实际路线：未确定'), findsOneWidget);
      expect(state.queries, isEmpty);
    });
  }
  testWidgets('研讨室子菜单读完返回后路线不冒充菜单实际读取', (tester) async {
    final state = await _open(tester, FeatureId.cgyy);
    await tester.tap(find.widgetWithText(Card, '我的预约'));
    await tester.pumpAndSettle();
    expect(state.queries.single.view, FeatureQueryView.cgyyOrders);
    expect(find.widgetWithText(AppBar, '我的预约'), findsOneWidget);
    expect(find.byTooltip('实际路线：WebVPN'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '研讨室预约'), findsOneWidget);
    expect(find.byTooltip('实际路线：未确定'), findsOneWidget);
    expect(state.queries, hasLength(1));
  });
  for (final feature in [FeatureId.cgyy, FeatureId.libbook]) {
    testWidgets('${feature.title}再次点击功能入口先回子菜单', (tester) async {
      final state = await _open(tester, feature);
      await tester.tap(find.widgetWithText(Card, '我的预约'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byType(NavigationDestination).at(UiDestination.campus.index),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Card, feature.title));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey(('feature-landing', feature))),
        findsOneWidget,
      );
      expect(state.queries, hasLength(1));
      await tester.tap(find.widgetWithText(Card, '我的预约'));
      await tester.pumpAndSettle();
      expect(find.text('合成子结果'), findsOneWidget);
      expect(state.queries, hasLength(2));
    });
  }
  testWidgets('当前预约记录失效后重读首批，等待期间保留返回菜单路径', (tester) async {
    final state = await _open(tester, FeatureId.cgyy);
    await tester.tap(find.widgetWithText(Card, '我的预约'));
    await tester.pumpAndSettle();
    state.pending = Completer<void>();
    state.invalidate();
    await tester.pump();
    await tester.pump();
    expect(state.queries, hasLength(2));
    expect(state.queries.last.view, FeatureQueryView.cgyyOrders);
    expect(state.queries.last.page, 0);
    expect(find.text('合成子结果'), findsNothing);
    expect(find.text('暂无研讨室预约数据'), findsNothing);
    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    expect(find.widgetWithText(Card, '预约研讨室'), findsOneWidget);
    state.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Card, '预约研讨室'), findsOneWidget);
    expect(find.text('合成子结果'), findsNothing);
  });
  testWidgets('后台预约记录失效不自动读取，重新进入菜单后读取恢复', (tester) async {
    final state = await _open(tester, FeatureId.cgyy);
    await tester.tap(find.widgetWithText(Card, '我的预约'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byType(NavigationDestination).at(UiDestination.campus.index),
    );
    await tester.pumpAndSettle();
    state.invalidate();
    await tester.pumpAndSettle();
    expect(state.queries, hasLength(1));
    await tester.tap(find.widgetWithText(Card, FeatureId.cgyy.title));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Card, '预约研讨室'), findsOneWidget);
    expect(state.queries, hasLength(1));
    await tester.tap(find.widgetWithText(Card, '我的预约'));
    await tester.pumpAndSettle();
    expect(find.text('合成子结果'), findsOneWidget);
    expect(state.queries, hasLength(2));
  });
  testWidgets('失效重读失败显示真实错误且只在手动重试后再次读取', (tester) async {
    final state = await _open(tester, FeatureId.cgyy);
    await tester.tap(find.widgetWithText(Card, '我的预约'));
    await tester.pumpAndSettle();
    state.failRead = true;
    state.invalidate();
    await tester.pumpAndSettle();
    expect(state.queries, hasLength(2));
    expect(find.text('合成读取失败'), findsOneWidget);
    expect(find.text('暂无研讨室预约数据'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(state.queries, hasLength(2));
    state.failRead = false;
    await tester.tap(find.widgetWithText(TextButton, '重试'));
    await tester.pumpAndSettle();
    expect(state.queries, hasLength(3));
    expect(state.queries.last.page, 0);
    expect(find.text('合成子结果'), findsOneWidget);
  });
  testWidgets('菜单中的预载内容失效后选择课程必须重新读取', (tester) async {
    final state = await _open(tester, FeatureId.bykc);
    state.invalidate();
    await tester.pumpAndSettle();
    expect(state.queries, isEmpty);
    await tester.tap(find.widgetWithText(Card, '选择课程'));
    await tester.pumpAndSettle();
    expect(state.queries, hasLength(1));
    expect(find.text('合成子结果'), findsOneWidget);
    expect(find.text('合成预载结果'), findsNothing);
  });
  testWidgets('子菜单请求中返回后迟到结果不能替换菜单', (tester) async {
    final state = await _open(tester, FeatureId.libbook);
    state.pending = Completer<void>();
    await tester.tap(find.widgetWithText(Card, '我的预约'));
    await tester.pump();
    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    state.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Card, '预约座位'), findsOneWidget);
    expect(find.text('合成子结果'), findsNothing);
    expect(find.byTooltip('实际路线：未确定'), findsOneWidget);
    expect(state.queries.single.view, FeatureQueryView.libbookBookings);
  });
}

Future<_HarnessState> _open(WidgetTester tester, FeatureId feature) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(402, 874);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(
    MaterialApp(
      home: _Harness(key: key, feature: feature),
    ),
  );
  await tester.pumpAndSettle();
  final card = find.widgetWithText(Card, feature.title);
  if (card.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      card,
      200,
      scrollable: find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    );
  }
  await tester.ensureVisible(card);
  await tester.tap(card);
  await tester.pumpAndSettle();
  return key.currentState!;
}

class _Harness extends StatefulWidget {
  const _Harness({required this.feature, super.key});
  final FeatureId feature;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final queries = <FeatureQuery>[];
  Completer<void>? pending;
  int revision = 1, epoch = 0;
  bool failRead = false;
  void invalidate() => setState(() => epoch++);
  void fail() => setState(
    () => snapshot = FeatureSnapshot(
      feature: widget.feature,
      status: FeatureLoadStatus.failure,
      error: const UiError(
        code: UbaaErrorCode.networkError,
        title: '网络不可用',
        message: '请稍后重试',
        retryable: true,
      ),
    ),
  );
  late FeatureSnapshot snapshot = FeatureSnapshot(
    feature: widget.feature,
    status: FeatureLoadStatus.success,
    resolvedRoute: ConnectionMode.direct,
    details: const [FeatureDetail(title: '合成预载结果')],
  );
  @override
  Widget build(BuildContext context) => UbaaMainShell(
    user: const UserSummary(username: 'synthetic'),
    readCacheEpoch: epoch,
    initialDestination: UiDestination.forFeature(widget.feature),
    snapshots: {
      for (final id in FeatureId.values)
        id: id == widget.feature ? snapshot : FeatureSnapshot(feature: id),
    },
    routePolicy: RoutePolicy.auto,
    telemetryEnabled: false,
    onRefresh: () async {},
    onRetryFeature: (_) async {},
    onFeatureQuery: (_, query) async {
      queries.add(query);
      final read = FeatureReadContext(
        query: query,
        requestRevision: ++revision,
      );
      setState(
        () => snapshot = FeatureSnapshot(
          feature: widget.feature,
          status: FeatureLoadStatus.loading,
          readContext: read,
        ),
      );
      if (pending != null) await pending!.future;
      if (!mounted) return;
      setState(
        () => snapshot = FeatureSnapshot(
          feature: widget.feature,
          status: failRead
              ? FeatureLoadStatus.failure
              : FeatureLoadStatus.success,
          error: failRead
              ? const UiError(
                  code: UbaaErrorCode.networkError,
                  title: '合成读取失败',
                  message: '请重试',
                  retryable: true,
                )
              : null,
          readContext: read,
          resolvedRoute: ConnectionMode.webvpn,
          details: failRead ? const [] : const [FeatureDetail(title: '合成子结果')],
        ),
      );
    },
    onLogout: () async {},
    onLogoutAndClearAccount: () async {},
    onRoutePolicyChanged: (_) {},
    onTelemetryChanged: (_) {},
  );
}

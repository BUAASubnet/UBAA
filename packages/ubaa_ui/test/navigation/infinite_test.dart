import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_ui/src/common/read_navigator.dart';
import '../support/navigation.dart';

void main() {
  testWidgets('同账号后台刷新保留分页内容、滚动位置和当前查询', (tester) async {
    final key = GlobalKey<_HarnessState>();
    tester.view.physicalSize = const Size(800, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: _Harness(key: key),
      ),
    );
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.bykc);
    final list = find.byType(ListView).last;
    await tester.drag(list, const Offset(0, -1200));
    await tester.pumpAndSettle();
    final scroll = find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scroll).position.pixels;
    final state = key.currentState!;
    final reads = state.requests.length;
    state.sessionRefresh();
    await tester.pumpAndSettle();
    expect(state.requests.length, reads);
    expect(
      tester.state<ScrollableState>(scroll).position.pixels,
      closeTo(position, 1),
    );
    expect(find.text('列表需要更新'), findsNothing);
    await state.read(FeatureId.bykc, state.requests.last);
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(scroll).position.pixels,
      closeTo(position, 1),
      reason: '恢复响应到达后也必须保留多页列表的滚动位置',
    );
    final restored = tester.state<FeatureReadNavigatorState>(
      find.byType(FeatureReadNavigator),
    );
    expect(restored.currentFrame.snapshot.details, hasLength(20));
    expect(
      restored.currentFrame.snapshot.details.every(
        (item) => item.title.startsWith('新项目'),
      ),
      isTrue,
    );
  });

  testWidgets('滚动追加保留前页，失败显式重试，详情返回保留位置，刷新重置首屏', (tester) async {
    final key = GlobalKey<_HarnessState>();
    tester.view.physicalSize = const Size(800, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: _Harness(key: key),
      ),
    );
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.bykc);
    final state = key.currentState!;
    final list = find.byType(ListView).last;
    final scroll = find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first;
    state.failNext = true;
    await tester.drag(list, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(state.requests.map((q) => q.page), [2]);
    expect(find.text('重试'), findsOneWidget);
    final position = tester.state<ScrollableState>(scroll).position;
    final beforeRetry = position.pixels;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(state.requests.map((q) => q.page), [2, 2]);
    expect(
      tester.state<ScrollableState>(scroll).position.pixels,
      closeTo(beforeRetry, 1),
    );
    await tester.scrollUntilVisible(find.text('项目12'), 250, scrollable: scroll);
    final beforeDetail = tester.state<ScrollableState>(scroll).position.pixels;
    await tester.tap(find.text('项目12'));
    await tester.pumpAndSettle();
    expect(find.text('合成详情'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    final restored = tester.state<ScrollableState>(scroll).position;
    expect(restored.pixels, closeTo(beforeDetail, 1));
    restored.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('项目0'), findsOneWidget);
    final beforeRefresh = state.requests.length;
    await tester.tap(find.byTooltip('刷新当前查询'));
    await tester.pumpAndSettle();
    expect(
      state.requests.skip(beforeRefresh).map((q) => q.page),
      [1, 2],
      reason: '刷新从首页开始并允许成功后的预取',
    );
    expect(find.text('项目0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('追加在途重复滚动只请求一次，清理缓存拒绝迟到追加并等待显式刷新', (tester) async {
    final key = GlobalKey<_HarnessState>();
    tester.view.physicalSize = const Size(800, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: _Harness(key: key),
      ),
    );
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.bykc);
    final state = key.currentState!;
    state.gate = Completer<void>();
    final list = find.byType(ListView).last;
    await tester.drag(list, const Offset(0, -3000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(list, const Offset(0, -100));
    await tester.pump();
    expect(state.requests.length, 1);
    state.invalidate();
    await tester.pump();
    state.gate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.requests.map((q) => q.page), [2]);
    expect(find.text('项目10'), findsNothing);
    await tester.tap(find.byTooltip('刷新当前查询'));
    await tester.pumpAndSettle();
    expect(state.requests.map((q) => q.page), [2, 1, 2]);
    expect(find.text('新项目0'), findsOneWidget);
    expect(find.text('项目10'), findsNothing, reason: '迟到的旧代次不能进入新列表');
    expect(tester.takeException(), isNull);
  });
}

class _Harness extends StatefulWidget {
  const _Harness({super.key});
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final requests = <FeatureQuery>[];
  Completer<void>? gate;
  bool failNext = false;
  int revision = 0, epoch = 0, contentEpoch = 0;
  late FeatureSnapshot snapshot = result(const FeatureQuery());
  FeatureSnapshot result(FeatureQuery query) => FeatureSnapshot(
    feature: FeatureId.bykc,
    status: FeatureLoadStatus.success,
    resolvedRoute: ConnectionMode.direct,
    readContext: FeatureReadContext(query: query, requestRevision: revision),
    pagination: query.view == FeatureQueryView.bykcDetail
        ? null
        : FeaturePagination(
            page: query.page <= 0 ? 1 : query.page,
            size: 10,
            total: 20,
          ),
    details: query.view == FeatureQueryView.bykcDetail
        ? const [FeatureDetail(title: '合成详情')]
        : [
            for (
              var i = ((query.page <= 0 ? 1 : query.page) - 1) * 10;
              i < (query.page <= 0 ? 1 : query.page) * 10;
              i++
            )
              FeatureDetail(
                title: '${epoch == 0 ? '' : '新'}项目$i',
                presentation: BykcCoursePresentation(
                  id: i + 1,
                  courseName: '${epoch == 0 ? '' : '新'}项目$i',
                  status: BykcCourseStatus.available,
                ),
                readNavigation: FeatureReadNavigation(
                  feature: FeatureId.bykc,
                  query: FeatureQuery(
                    view: FeatureQueryView.bykcDetail,
                    courseId: '$i',
                  ),
                ),
              ),
          ],
  );
  void invalidate() => setState(() {
    epoch++;
    contentEpoch++;
  });
  void sessionRefresh() => setState(() => epoch++);
  Future<void> read(FeatureId id, FeatureQuery query) async {
    requests.add(query);
    revision++;
    final next = result(query);
    setState(
      () => snapshot = snapshot.copyWith(
        status: FeatureLoadStatus.loading,
        readContext: next.readContext,
      ),
    );
    if (gate != null) await gate!.future;
    setState(() {
      snapshot = failNext
          ? next.copyWith(
              status: FeatureLoadStatus.failure,
              clearDetails: true,
              error: const UiError(
                code: UbaaErrorCode.networkError,
                title: '合成错误',
                message: '失败',
              ),
            )
          : next;
      failNext = false;
    });
  }

  @override
  Widget build(BuildContext context) => UbaaMainShell(
    user: const UserSummary(username: 'synthetic'),
    readCacheEpoch: epoch,
    businessCacheEpoch: contentEpoch,
    snapshots: {
      for (final id in FeatureId.values)
        id: id == FeatureId.bykc ? snapshot : FeatureSnapshot(feature: id),
    },
    routePolicy: RoutePolicy.auto,
    telemetryEnabled: false,
    onRefresh: () async {},
    onRetryFeature: (_) async {},
    onFeatureQuery: read,
    onLogout: () async {},
    onLogoutAndClearAccount: () async {},
    onRoutePolicyChanged: (_) {},
    onTelemetryChanged: (_) {},
  );
}
